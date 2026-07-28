const types = @import("types.zig");
const Object = types.Object;

pub const FileInfo = struct {
    header: Object,
    size: i64,
    mtime: i64,
    atime: i64,
    ctime: i64,
    dev: i64,
    ino: i64,
    nlinks: i64,
    rdev: i64,
    blksize: i64,
    blocks: i64,
    mode: u32,
    uid: u32,
    gid: u32,
    file_type: FileType,

    pub const FileType = enum(u8) { regular, directory, symlink, fifo, socket, char_device, block_device, other };
};

pub const UserInfo = struct {
    header: Object,
    name: []const u8,
    uid: u32,
    gid: u32,
    home_dir: []const u8,
    shell: []const u8,
    full_name: []const u8,
};

pub const GroupInfo = struct {
    header: Object,
    name: []const u8,
    gid: u32,
};

pub const DirectoryObject = struct {
    header: Object,
    dir: ?*anyopaque,
    include_dotfiles: bool,
};
