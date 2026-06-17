const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const GC = @import("memory.zig").GC;

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
    try primitives.reg(vm, "create-directory", &createDirectoryFn, .{ .variadic = 1 });
    try primitives.reg(vm, "delete-directory", &deleteDirectoryFn, .{ .exact = 1 });
}

fn raiseFileError(gc: *GC, msg_text: []const u8, irritant: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const msg = gc.allocString(msg_text) catch return PrimitiveError.OutOfMemory;
    const irritants = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
    const err_obj = gc.allocErrorObject(msg, irritants) catch return PrimitiveError.OutOfMemory;
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
    const path = extractPath(args[0]) orelse return PrimitiveError.TypeError;
    const include_dotfiles = if (args.len > 1) types.isTruthy(args[1]) else false;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const dir = std.c.opendir(path_z) orelse {
        return raiseFileError(gc, "cannot open directory", args[0]);
    };
    defer _ = std.c.closedir(dir);

    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();

    while (std.c.readdir(dir)) |entry| {
        const name_ptr: [*]const u8 = @ptrCast(&entry.name);
        const name = name_ptr[0..entry.namlen];

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
    const path = extractPath(args[0]) orelse return PrimitiveError.TypeError;
    const follow = if (args.len > 1) types.isTruthy(args[1]) else true;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    var stat_buf: std.c.Stat = undefined;
    const flags: u32 = if (!follow) std.c.AT.SYMLINK_NOFOLLOW else 0;
    const r = std.c.fstatat(std.posix.AT.FDCWD, path_z, &stat_buf, flags);
    if (r != 0) {
        return raiseFileError(gc, "cannot stat file", args[0]);
    }

    const mode: u32 = @intCast(stat_buf.mode);
    const file_type: types.FileInfo.FileType = blk: {
        const masked = mode & std.c.S.IFMT;
        if (masked == std.c.S.IFDIR) break :blk .directory;
        if (masked == std.c.S.IFREG) break :blk .regular;
        if (masked == std.c.S.IFLNK) break :blk .symlink;
        break :blk .other;
    };

    const perm_bits: u16 = @truncate(mode & 0o7777);
    const mtime_sec: i64 = stat_buf.mtime().sec;

    return gc.allocFileInfo(
        @intCast(stat_buf.size),
        mtime_sec,
        perm_bits,
        file_type,
    ) catch return PrimitiveError.OutOfMemory;
}

// -------------------------------------------------------------------------
// Predicates
// -------------------------------------------------------------------------

fn fileInfoP(args: []const Value) PrimitiveError!Value {
    return if (types.isFileInfo(args[0])) types.TRUE else types.FALSE;
}

fn fileInfoDirectoryP(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return PrimitiveError.TypeError;
    return if (types.toFileInfo(args[0]).file_type == .directory) types.TRUE else types.FALSE;
}

fn fileInfoRegularP(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return PrimitiveError.TypeError;
    return if (types.toFileInfo(args[0]).file_type == .regular) types.TRUE else types.FALSE;
}

fn fileInfoSymlinkP(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return PrimitiveError.TypeError;
    return if (types.toFileInfo(args[0]).file_type == .symlink) types.TRUE else types.FALSE;
}

// -------------------------------------------------------------------------
// Accessors
// -------------------------------------------------------------------------

fn fileInfoSize(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return PrimitiveError.TypeError;
    return types.makeFixnum(types.toFileInfo(args[0]).size);
}

fn fileInfoMtime(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return PrimitiveError.TypeError;
    return types.makeFixnum(types.toFileInfo(args[0]).mtime);
}

fn fileInfoMode(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return PrimitiveError.TypeError;
    return types.makeFixnum(@as(i64, types.toFileInfo(args[0]).mode));
}

// -------------------------------------------------------------------------
// (create-directory path [mode])
// (delete-directory path)
// -------------------------------------------------------------------------

fn createDirectoryFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return PrimitiveError.TypeError;

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
    const path = extractPath(args[0]) orelse return PrimitiveError.TypeError;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    if (std.c.rmdir(path_z) != 0) {
        return raiseFileError(gc, "cannot delete directory", args[0]);
    }
    return types.VOID;
}
