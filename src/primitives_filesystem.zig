const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const GC = @import("memory.zig").GC;

extern fn mkstemp(template: [*:0]u8) c_int;

extern "c" fn truncate(path: [*:0]const u8, length: std.c.off_t) c_int;
extern "c" fn mkfifo(path: [*:0]const u8, mode: std.c.mode_t) c_int;
extern "c" fn chown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;
extern "c" fn getgroups(size: c_int, list: [*]std.c.gid_t) c_int;
extern "c" fn nice(inc: c_int) c_int;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
const is_linux = @import("builtin").os.tag == .linux;

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
    uid: u32,
    gid: u32,
};

fn doStat(path: [*:0]const u8, follow: bool) ?StatResult {
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
            .dev = @intCast(sx.dev_major),
            .ino = sx.ino,
            .nlinks = sx.nlink,
            .rdev = @intCast(sx.rdev_major),
            .blksize = @intCast(sx.blksize),
            .uid = sx.uid,
            .gid = sx.gid,
        };
    } else {
        const lstat_fn = @extern(*const fn ([*:0]const u8, *std.c.Stat) callconv(.c) c_int, .{ .name = "lstat" });
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
            .uid = stat_buf.uid,
            .gid = stat_buf.gid,
        };
    }
}

pub fn registerFilesystem(vm: *vm_mod.VM) !void {
    try primitives.reg(vm, "directory-files", &directoryFiles, .{ .variadic = 1 });
    try primitives.reg(vm, "file-info", &fileInfoFn, .{ .variadic = 1 });
    try primitives.reg(vm, "file-info?", &fileInfoP, .{ .exact = 1 });
    try primitives.reg(vm, "file-info-directory?", &fileInfoDirectoryP, .{ .exact = 1 });
    try primitives.reg(vm, "file-info-regular?", &fileInfoRegularP, .{ .exact = 1 });
    try primitives.reg(vm, "file-info-symlink?", &fileInfoSymlinkP, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:size", &fileInfoSize, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:mtime", &fileInfoMtime, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:mode", &fileInfoMode, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:device", &fileInfoDevice, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:inode", &fileInfoInode, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:nlinks", &fileInfoNlinks, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:uid", &fileInfoUid, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:gid", &fileInfoGid, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:rdev", &fileInfoRdev, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:blksize", &fileInfoBlksize, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:blocks", &fileInfoBlocks, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:atime", &fileInfoAtime, .{ .exact = 1 });
    try primitives.reg(vm, "file-info:ctime", &fileInfoCtime, .{ .exact = 1 });
    try primitives.reg(vm, "file-info-fifo?", &fileInfoFifoP, .{ .exact = 1 });
    try primitives.reg(vm, "file-info-socket?", &fileInfoSocketP, .{ .exact = 1 });
    try primitives.reg(vm, "file-info-device?", &fileInfoDeviceP, .{ .exact = 1 });
    try primitives.reg(vm, "create-directory", &createDirectoryFn, .{ .variadic = 1 });
    try primitives.reg(vm, "delete-directory", &deleteDirectoryFn, .{ .exact = 1 });

    // File system operations
    try primitives.reg(vm, "rename-file", &renameFileFn, .{ .exact = 2 });
    try primitives.reg(vm, "create-symlink", &createSymlinkFn, .{ .exact = 2 });
    try primitives.reg(vm, "read-symlink", &readSymlinkFn, .{ .exact = 1 });
    try primitives.reg(vm, "create-hard-link", &createHardLinkFn, .{ .exact = 2 });
    try primitives.reg(vm, "real-path", &realPathFn, .{ .exact = 1 });
    try primitives.reg(vm, "set-file-mode", &setFileModeFn, .{ .exact = 2 });
    try primitives.reg(vm, "truncate-file", &truncateFileFn, .{ .exact = 2 });
    try primitives.reg(vm, "create-fifo", &createFifoFn, .{ .variadic = 1 });
    try primitives.reg(vm, "set-file-owner", &setFileOwnerFn, .{ .exact = 3 });
    try primitives.reg(vm, "set-file-times", &setFileTimesFn, .{ .variadic = 1 });

    try primitives.reg(vm, "file-info-type", &fileInfoTypeFn, .{ .exact = 1 });
    try primitives.reg(vm, "temp-file-prefix", &tempFilePrefixFn, .{ .exact = 0 });
    try primitives.reg(vm, "create-temp-file", &createTempFileFn, .{ .variadic = 0 });

    // Process state
    try primitives.reg(vm, "pid", &pidFn, .{ .exact = 0 });
    try primitives.reg(vm, "umask", &umaskFn, .{ .exact = 0 });
    try primitives.reg(vm, "set-umask!", &setUmaskFn, .{ .exact = 1 });
    try primitives.reg(vm, "current-directory", &currentDirectoryFn, .{ .exact = 0 });
    try primitives.reg(vm, "set-current-directory!", &setCurrentDirectoryFn, .{ .exact = 1 });
    try primitives.reg(vm, "user-uid", &userUidFn, .{ .exact = 0 });
    try primitives.reg(vm, "user-gid", &userGidFn, .{ .exact = 0 });
    try primitives.reg(vm, "user-effective-uid", &userEffectiveUidFn, .{ .exact = 0 });
    try primitives.reg(vm, "user-effective-gid", &userEffectiveGidFn, .{ .exact = 0 });
    try primitives.reg(vm, "user-supplementary-gids", &userSupplementaryGidsFn, .{ .exact = 0 });
    try primitives.reg(vm, "nice", &niceFn, .{ .variadic = 0 });

    // Environment variables
    try primitives.reg(vm, "set-environment-variable!", &setEnvVarFn, .{ .exact = 2 });
    try primitives.reg(vm, "delete-environment-variable!", &deleteEnvVarFn, .{ .exact = 1 });

    // Terminal
    try primitives.reg(vm, "terminal?", &terminalP, .{ .exact = 1 });

    // User/group database
    try primitives.reg(vm, "user-info", &userInfoFn, .{ .exact = 1 });
    try primitives.reg(vm, "user-info?", &userInfoP, .{ .exact = 1 });
    try primitives.reg(vm, "user-info:name", &userInfoName, .{ .exact = 1 });
    try primitives.reg(vm, "user-info:uid", &userInfoUid, .{ .exact = 1 });
    try primitives.reg(vm, "user-info:gid", &userInfoGidFn, .{ .exact = 1 });
    try primitives.reg(vm, "user-info:home-dir", &userInfoHomeDir, .{ .exact = 1 });
    try primitives.reg(vm, "user-info:shell", &userInfoShell, .{ .exact = 1 });
    try primitives.reg(vm, "user-info:full-name", &userInfoFullName, .{ .exact = 1 });
    try primitives.reg(vm, "group-info", &groupInfoFn, .{ .exact = 1 });
    try primitives.reg(vm, "group-info?", &groupInfoP, .{ .exact = 1 });
    try primitives.reg(vm, "group-info:name", &groupInfoName, .{ .exact = 1 });
    try primitives.reg(vm, "group-info:gid", &groupInfoGidFn, .{ .exact = 1 });

    // Directory traversal
    try primitives.reg(vm, "open-directory", &openDirectoryFn, .{ .variadic = 1 });
    try primitives.reg(vm, "read-directory", &readDirectoryFn, .{ .exact = 1 });
    try primitives.reg(vm, "close-directory", &closeDirectoryFn, .{ .exact = 1 });

    // POSIX time
    try primitives.reg(vm, "posix-time", &posixTimeFn, .{ .exact = 0 });
    try primitives.reg(vm, "monotonic-time", &monotonicTimeFn, .{ .exact = 0 });
}

fn raiseFileError(gc: *GC, msg_text: []const u8, irritant: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    var msg = gc.allocString(msg_text) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    const irritants = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
    var irritants_root = irritants;
    gc.pushRoot(&irritants_root) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, irritants_root) catch return PrimitiveError.OutOfMemory;
    types.toObject(err_obj).as(types.ErrorObject).error_type = .file;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

fn extractPath(val: Value) ?[]const u8 {
    if (!types.isString(val)) return null;
    const str = types.toObject(val).as(types.SchemeString);
    return str.data[0..str.len];
}

// -------------------------------------------------------------------------
// (directory-files dir [dotfiles?])
// -------------------------------------------------------------------------

fn directoryFiles(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("directory-files", "string", args[0]);
    const include_dotfiles = if (args.len > 1) types.isTruthy(args[1]) else false;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const dir = std.c.opendir(path_z) orelse {
        return raiseFileError(gc, "cannot open directory", args[0]);
    };
    defer _ = std.c.closedir(dir);

    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    while (std.c.readdir(dir)) |entry| {
        const name_ptr: [*:0]const u8 = @ptrCast(&entry.name);
        const name = std.mem.span(name_ptr);

        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (!include_dotfiles and name.len > 0 and name[0] == '.') continue;

        const str_val = gc.allocString(name) catch return PrimitiveError.OutOfMemory;
        result = gc.allocPair(str_val, result) catch return PrimitiveError.OutOfMemory;
    }

    return result;
}

// -------------------------------------------------------------------------
// (file-info path [follow?])
// -------------------------------------------------------------------------

fn fileInfoFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("file-info", "string", args[0]);
    const follow = if (args.len > 1) types.isTruthy(args[1]) else true;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const sr = doStat(path_z, follow) orelse {
        return raiseFileError(gc, "cannot stat file", args[0]);
    };

    const S = std.c.S;
    const file_type: types.FileInfo.FileType = blk: {
        const masked = sr.mode & S.IFMT;
        if (masked == S.IFDIR) break :blk .directory;
        if (masked == S.IFREG) break :blk .regular;
        if (masked == S.IFLNK) break :blk .symlink;
        if (masked == S.IFIFO) break :blk .fifo;
        if (masked == S.IFSOCK) break :blk .socket;
        if (masked == S.IFCHR or masked == S.IFBLK) break :blk .device;
        break :blk .other;
    };

    return gc.allocFileInfo(.{
        .size = @intCast(sr.size),
        .mtime = sr.mtime_sec,
        .atime = sr.atime_sec,
        .ctime = sr.ctime_sec,
        .dev = @intCast(sr.dev),
        .ino = @intCast(sr.ino),
        .nlinks = @intCast(sr.nlinks),
        .rdev = @intCast(sr.rdev),
        .blksize = @intCast(sr.blksize),
        .blocks = 0,
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
    return types.makeFixnum(types.toFileInfo(args[0]).size);
}

fn fileInfoMtime(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:mtime", "file-info", args[0]);
    return types.makeFixnum(types.toFileInfo(args[0]).mtime);
}

fn fileInfoMode(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:mode", "file-info", args[0]);
    return types.makeFixnum(@as(i64, @intCast(types.toFileInfo(args[0]).mode)));
}

fn fileInfoDevice(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:device", "file-info", args[0]);
    return types.makeFixnum(types.toFileInfo(args[0]).dev);
}

fn fileInfoInode(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:inode", "file-info", args[0]);
    return types.makeFixnum(types.toFileInfo(args[0]).ino);
}

fn fileInfoNlinks(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:nlinks", "file-info", args[0]);
    return types.makeFixnum(types.toFileInfo(args[0]).nlinks);
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
    return types.makeFixnum(types.toFileInfo(args[0]).rdev);
}

fn fileInfoBlksize(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:blksize", "file-info", args[0]);
    return types.makeFixnum(types.toFileInfo(args[0]).blksize);
}

fn fileInfoBlocks(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:blocks", "file-info", args[0]);
    return types.makeFixnum(types.toFileInfo(args[0]).blocks);
}

fn fileInfoAtime(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:atime", "file-info", args[0]);
    return types.makeFixnum(types.toFileInfo(args[0]).atime);
}

fn fileInfoCtime(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:ctime", "file-info", args[0]);
    return types.makeFixnum(types.toFileInfo(args[0]).ctime);
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
    return if (types.toFileInfo(args[0]).file_type == .device) types.TRUE else types.FALSE;
}

// -------------------------------------------------------------------------
// (create-directory path [mode])
// (delete-directory path)
// -------------------------------------------------------------------------

fn createDirectoryFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("create-directory", "string", args[0]);

    const mode: std.c.mode_t = if (args.len > 1 and types.isFixnum(args[1]))
        @intCast(@as(u64, @bitCast(types.toFixnum(args[1]))))
    else
        0o755;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    if (std.c.mkdir(path_z, mode) != 0) {
        return raiseFileError(gc, "cannot create directory", args[0]);
    }
    return types.VOID;
}

fn deleteDirectoryFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("delete-directory", "string", args[0]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    if (std.c.rmdir(path_z) != 0) {
        return raiseFileError(gc, "cannot delete directory", args[0]);
    }
    return types.VOID;
}

// -------------------------------------------------------------------------
// File system operations (SRFI-170 §3.3)
// -------------------------------------------------------------------------

fn renameFileFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const old = extractPath(args[0]) orelse return primitives.typeError("rename-file", "string", args[0]);
    const new = extractPath(args[1]) orelse return primitives.typeError("rename-file", "string", args[1]);

    const old_z = gc.allocator.dupeZ(u8, old) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(old_z);
    const new_z = gc.allocator.dupeZ(u8, new) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(new_z);

    if (std.c.rename(old_z, new_z) != 0) {
        return raiseFileError(gc, "cannot rename file", args[0]);
    }
    return types.VOID;
}

fn createSymlinkFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const old = extractPath(args[0]) orelse return primitives.typeError("create-symlink", "string", args[0]);
    const new = extractPath(args[1]) orelse return primitives.typeError("create-symlink", "string", args[1]);

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
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("read-symlink", "string", args[0]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    var buf: [std.posix.PATH_MAX]u8 = undefined;
    const r = std.c.readlink(path_z, &buf, buf.len);
    if (r < 0) {
        return raiseFileError(gc, "cannot read symlink", args[0]);
    }
    return gc.allocString(buf[0..@intCast(r)]) catch return PrimitiveError.OutOfMemory;
}

fn createHardLinkFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const old = extractPath(args[0]) orelse return primitives.typeError("create-hard-link", "string", args[0]);
    const new = extractPath(args[1]) orelse return primitives.typeError("create-hard-link", "string", args[1]);

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
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("real-path", "string", args[0]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    var resolved_buf: [std.posix.PATH_MAX]u8 = undefined;
    const resolved = std.c.realpath(path_z, &resolved_buf) orelse {
        return raiseFileError(gc, "cannot resolve path", args[0]);
    };
    const len = std.mem.indexOfScalar(u8, resolved[0..resolved_buf.len], 0) orelse resolved_buf.len;
    return gc.allocString(resolved[0..len]) catch return PrimitiveError.OutOfMemory;
}

fn setFileModeFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("set-file-mode", "string", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("set-file-mode", "integer", args[1]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const mode: std.c.mode_t = @intCast(@as(u64, @bitCast(types.toFixnum(args[1]))));
    if (std.c.chmod(path_z, mode) != 0) {
        return raiseFileError(gc, "cannot set file mode", args[0]);
    }
    return types.VOID;
}

fn truncateFileFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("truncate-file", "string", args[0]);
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
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("create-fifo", "string", args[0]);

    const mode: std.c.mode_t = if (args.len > 1 and types.isFixnum(args[1]))
        @intCast(@as(u64, @bitCast(types.toFixnum(args[1]))))
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
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("set-file-owner", "string", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("set-file-owner", "integer", args[1]);
    if (!types.isFixnum(args[2])) return primitives.typeError("set-file-owner", "integer", args[2]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const uid_val = types.toFixnum(args[1]);
    const gid_val = types.toFixnum(args[2]);
    const owner: std.c.uid_t = if (uid_val < 0) @bitCast(@as(u32, 0xFFFFFFFF)) else @intCast(@as(u64, @bitCast(uid_val)));
    const group: std.c.gid_t = if (gid_val < 0) @bitCast(@as(u32, 0xFFFFFFFF)) else @intCast(@as(u64, @bitCast(gid_val)));

    if (chown(path_z, owner, group) != 0) {
        return raiseFileError(gc, "cannot set file owner", args[0]);
    }
    return types.VOID;
}

const TIME_NOW: i64 = -1;
const TIME_UNCHANGED: i64 = -2;

fn setFileTimesFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("set-file-times", "string", args[0]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    var times: [2]std.c.timespec = undefined;

    if (args.len > 1 and types.isFixnum(args[1])) {
        const atime_val = types.toFixnum(args[1]);
        if (atime_val == TIME_NOW) {
            times[0] = std.c.UTIME.NOW;
        } else if (atime_val == TIME_UNCHANGED) {
            times[0] = std.c.UTIME.OMIT;
        } else {
            times[0] = .{ .sec = @intCast(atime_val), .nsec = 0 };
        }
    } else {
        times[0] = std.c.UTIME.NOW;
    }

    if (args.len > 2 and types.isFixnum(args[2])) {
        const mtime_val = types.toFixnum(args[2]);
        if (mtime_val == TIME_NOW) {
            times[1] = std.c.UTIME.NOW;
        } else if (mtime_val == TIME_UNCHANGED) {
            times[1] = std.c.UTIME.OMIT;
        } else {
            times[1] = .{ .sec = @intCast(mtime_val), .nsec = 0 };
        }
    } else {
        times[1] = std.c.UTIME.NOW;
    }

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
    return types.makeFixnum(@as(i64, @intCast(std.c.getpid())));
}

fn umaskFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const cur = std.c.umask(0);
    _ = std.c.umask(cur);
    return types.makeFixnum(@as(i64, @intCast(cur)));
}

fn setUmaskFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return primitives.typeError("set-umask!", "integer", args[0]);
    const mask: std.c.mode_t = @intCast(@as(u64, @bitCast(types.toFixnum(args[0]))));
    _ = std.c.umask(mask);
    return types.VOID;
}

fn currentDirectoryFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    var buf: [std.posix.PATH_MAX]u8 = undefined;
    const result = std.c.getcwd(&buf, buf.len) orelse {
        return raiseFileError(gc, "cannot get current directory", types.FALSE);
    };
    const len = std.mem.indexOfScalar(u8, result[0..buf.len], 0) orelse buf.len;
    return gc.allocString(result[0..len]) catch return PrimitiveError.OutOfMemory;
}

fn setCurrentDirectoryFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("set-current-directory!", "string", args[0]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    if (std.c.chdir(path_z) != 0) {
        return raiseFileError(gc, "cannot change directory", args[0]);
    }
    return types.VOID;
}

fn userUidFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.makeFixnum(@as(i64, @intCast(std.c.getuid())));
}

fn userGidFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.makeFixnum(@as(i64, @intCast(std.c.getgid())));
}

fn userEffectiveUidFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.makeFixnum(@as(i64, @intCast(std.c.geteuid())));
}

fn userEffectiveGidFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.makeFixnum(@as(i64, @intCast(std.c.getegid())));
}

fn userSupplementaryGidsFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    var gids: [64]std.c.gid_t = undefined;
    const n = getgroups(64, &gids);
    if (n < 0) return PrimitiveError.TypeError;

    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
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
    const delta: c_int = if (args.len > 0 and types.isFixnum(args[0]))
        @intCast(types.toFixnum(args[0]))
    else
        1;
    const result = nice(delta);
    return types.makeFixnum(@as(i64, @intCast(result)));
}

// -------------------------------------------------------------------------
// Environment variables (SRFI-170 §3.11)
// -------------------------------------------------------------------------

fn setEnvVarFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const name = extractPath(args[0]) orelse return primitives.typeError("set-environment-variable!", "string", args[0]);
    const value = extractPath(args[1]) orelse return primitives.typeError("set-environment-variable!", "string", args[1]);

    const name_z = gc.allocator.dupeZ(u8, name) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(name_z);
    const value_z = gc.allocator.dupeZ(u8, value) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(value_z);

    if (setenv(name_z, value_z, 1) != 0) {
        return raiseFileError(gc, "cannot set environment variable", args[0]);
    }
    return types.VOID;
}

fn deleteEnvVarFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const name = extractPath(args[0]) orelse return primitives.typeError("delete-environment-variable!", "string", args[0]);

    const name_z = gc.allocator.dupeZ(u8, name) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(name_z);

    _ = unsetenv(name_z);
    return types.VOID;
}

// -------------------------------------------------------------------------
// Terminal (SRFI-170 §3.12)
// -------------------------------------------------------------------------

fn terminalP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("terminal?", "port", args[0]);
    const port = types.toObject(args[0]).as(types.Port);
    return if (std.c.isatty(port.fd) != 0) types.TRUE else types.FALSE;
}

// -------------------------------------------------------------------------
// User/group database (SRFI-170 §3.6)
// -------------------------------------------------------------------------

fn userInfoFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    const pw = if (types.isFixnum(args[0])) blk: {
        const uid: std.c.uid_t = @intCast(@as(u64, @bitCast(types.toFixnum(args[0]))));
        break :blk std.c.getpwuid(uid);
    } else if (types.isString(args[0])) blk: {
        const name = extractPath(args[0]) orelse return primitives.typeError("user-info", "string or integer", args[0]);
        const name_z = gc.allocator.dupeZ(u8, name) catch return PrimitiveError.OutOfMemory;
        defer gc.allocator.free(name_z);
        break :blk std.c.getpwnam(name_z);
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
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(types.toUserInfo(args[0]).home_dir) catch return PrimitiveError.OutOfMemory;
}

fn userInfoShell(args: []const Value) PrimitiveError!Value {
    if (!types.isUserInfo(args[0])) return primitives.typeError("user-info:shell", "user-info", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(types.toUserInfo(args[0]).shell) catch return PrimitiveError.OutOfMemory;
}

fn userInfoFullName(args: []const Value) PrimitiveError!Value {
    if (!types.isUserInfo(args[0])) return primitives.typeError("user-info:full-name", "user-info", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(types.toUserInfo(args[0]).full_name) catch return PrimitiveError.OutOfMemory;
}

fn groupInfoFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    if (types.isFixnum(args[0])) {
        const gid: std.c.gid_t = @intCast(@as(u64, @bitCast(types.toFixnum(args[0]))));
        const g = std.c.getgrgid(gid) orelse return types.FALSE;
        const name_str = std.mem.span(g.name.?);
        return gc.allocGroupInfo(name_str, g.gid) catch return PrimitiveError.OutOfMemory;
    } else if (types.isString(args[0])) {
        const name = extractPath(args[0]) orelse return primitives.typeError("group-info", "string or integer", args[0]);
        const name_z = gc.allocator.dupeZ(u8, name) catch return PrimitiveError.OutOfMemory;
        defer gc.allocator.free(name_z);
        const g = std.c.getgrnam(name_z) orelse return types.FALSE;
        const name_str = std.mem.span(g.name.?);
        return gc.allocGroupInfo(name_str, g.gid) catch return PrimitiveError.OutOfMemory;
    } else return primitives.typeError("group-info", "string or integer", args[0]);
}

fn groupInfoP(args: []const Value) PrimitiveError!Value {
    return if (types.isGroupInfo(args[0])) types.TRUE else types.FALSE;
}

fn groupInfoName(args: []const Value) PrimitiveError!Value {
    if (!types.isGroupInfo(args[0])) return primitives.typeError("group-info:name", "group-info", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("open-directory", "string", args[0]);
    const include_dotfiles = if (args.len > 1) types.isTruthy(args[1]) else false;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const dir = std.c.opendir(path_z) orelse {
        return raiseFileError(gc, "cannot open directory", args[0]);
    };

    return gc.allocDirectoryObject(@ptrCast(dir), include_dotfiles) catch {
        _ = std.c.closedir(dir);
        return PrimitiveError.OutOfMemory;
    };
}

fn readDirectoryFn(args: []const Value) PrimitiveError!Value {
    if (!types.isDirectoryObject(args[0])) return primitives.typeError("read-directory", "directory-object", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const d = types.toDirectoryObject(args[0]);

    const dir_ptr = d.dir orelse return types.EOF;
    const dir: *std.c.DIR = @ptrCast(@alignCast(dir_ptr));

    while (std.c.readdir(dir)) |entry| {
        const name_ptr: [*:0]const u8 = @ptrCast(&entry.name);
        const name = std.mem.span(name_ptr);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (!d.include_dotfiles and name.len > 0 and name[0] == '.') continue;
        return gc.allocString(name) catch return PrimitiveError.OutOfMemory;
    }

    _ = std.c.closedir(dir);
    d.dir = null;
    return types.EOF;
}

fn closeDirectoryFn(args: []const Value) PrimitiveError!Value {
    if (!types.isDirectoryObject(args[0])) return primitives.typeError("close-directory", "directory-object", args[0]);
    const d = types.toDirectoryObject(args[0]);
    if (d.dir) |dir| {
        _ = std.c.closedir(@ptrCast(@alignCast(dir)));
        d.dir = null;
    }
    return types.VOID;
}

// -------------------------------------------------------------------------
// POSIX time (SRFI-170 §3.10)
// -------------------------------------------------------------------------

fn posixTimeFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.REALTIME, &ts);
    return types.makeFixnum(@as(i64, @intCast(ts.sec)));
}

fn monotonicTimeFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return types.makeFixnum(@as(i64, @intCast(ts.sec)));
}

// (file-info-type fi) — return type as symbol
fn fileInfoTypeFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info-type", "file-info", args[0]);
    const fi = types.toObject(args[0]).as(types.FileInfo);
    const name: []const u8 = switch (fi.file_type) {
        .regular => "regular",
        .directory => "directory",
        .symlink => "symlink",
        .fifo => "fifo",
        .socket => "socket",
        .device => "block-special",
        .other => "unknown",
    };
    return gc.allocSymbol(name) catch return PrimitiveError.OutOfMemory;
}

// (temp-file-prefix) — return tempdir path
fn tempFilePrefixFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString("/tmp/kaappi-") catch return PrimitiveError.OutOfMemory;
}

// (create-temp-file [prefix]) — create a temp file and return its path
fn createTempFileFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    var prefix: []const u8 = "/tmp/kaappi-";
    if (args.len > 0 and types.isString(args[0])) {
        const s = types.toObject(args[0]).as(types.SchemeString);
        prefix = s.data[0..s.len];
    }

    // Build template: prefix + XXXXXX + null
    var template_buf: [256]u8 = undefined;
    if (prefix.len + 7 > template_buf.len) return PrimitiveError.TypeError;
    @memcpy(template_buf[0..prefix.len], prefix);
    @memcpy(template_buf[prefix.len..][0..6], "XXXXXX");
    template_buf[prefix.len + 6] = 0;

    const fd = mkstemp(@ptrCast(template_buf[0 .. prefix.len + 6 :0]));
    if (fd < 0) return raiseFileError(gc, "cannot create temp file", types.FALSE);
    _ = std.posix.system.close(fd);

    // Find actual path length (null-terminated)
    var path_len: usize = 0;
    while (path_len < template_buf.len and template_buf[path_len] != 0) path_len += 1;

    return gc.allocString(template_buf[0..path_len]) catch return PrimitiveError.OutOfMemory;
}
