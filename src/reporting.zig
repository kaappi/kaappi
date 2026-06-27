const std = @import("std");
pub const types = @import("types.zig");
pub const memory = @import("memory.zig");
pub const vm_mod = @import("vm.zig");
pub const library_mod = @import("library.zig");

fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        if (result <= 0) break;
        total += @as(usize, @intCast(result));
    }
}

pub fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

pub fn printGcStats(gc: *memory.GC) void {
    const s = &gc.stats;
    const mark_ms = @as(f64, @floatFromInt(s.total_mark_ns)) / 1_000_000.0;
    const sweep_ms = @as(f64, @floatFromInt(s.total_sweep_ns)) / 1_000_000.0;
    var buf: [2048]u8 = undefined;

    const header = std.fmt.bufPrint(&buf,
        \\GC Statistics:
        \\  Collections:       {d}
        \\  Live objects:      {d} (peak: {d})
        \\  Heap size:         {d} bytes (peak: {d})
        \\  Freed:             {d} objects, {d} bytes
        \\  Mark time:         {d:.2} ms total
        \\  Sweep time:        {d:.2} ms total
        \\
    , .{
        s.collections,
        gc.object_count,
        s.peak_object_count,
        gc.bytes_allocated,
        s.peak_bytes_allocated,
        s.objects_freed,
        s.bytes_freed,
        mark_ms,
        sweep_ms,
    }) catch "";
    writeStderr(header);

    if (s.no_collect_deferred > 0) {
        const defer_line = std.fmt.bufPrint(&buf, "  No-collect defers: {d}\n", .{s.no_collect_deferred}) catch "";
        writeStderr(defer_line);
    }

    const type_names = [_][]const u8{
        "pair",      "symbol",    "string",    "closure",
        "native_fn", "vector",    "bytevec",   "port",
        "rec_type",  "function",  "flonum",    "xformer",
        "error",     "rec_inst",  "contin",    "multi_val",
        "complex",   "promise",   "parameter", "ffi_lib",
        "ffi_fn",    "hashtable", "bignum",    "rational",
        "file_info", "user_info", "grp_info",  "dir_obj",
        "rng",       "ffi_cb",    "fiber",     "channel",
        "mutex",     "condvar",   "time18",
    };

    writeStderr("  Allocations by type:\n");
    var col: usize = 0;
    for (type_names, 0..) |name, i| {
        const count = s.allocs_by_type[i];
        if (count == 0) continue;
        if (col == 0) writeStderr("    ");
        const entry = std.fmt.bufPrint(&buf, "{s: <10} {d: >8}  ", .{ name, count }) catch "";
        writeStderr(entry);
        col += 1;
        if (col >= 3) {
            writeStderr("\n");
            col = 0;
        }
    }
    if (col > 0) writeStderr("\n");
}

pub fn resetProfileCounters(gc: *memory.GC) void {
    var obj = gc.objects;
    while (obj) |o| {
        if (o.tag == .function) {
            const func = o.as(types.Function);
            func.profile_instrs = 0;
            func.profile_calls = 0;
            func.profile_time_ns = 0;
            func.profile_inclusive_ns = 0;
            func.profile_alloc_bytes = 0;
        } else if (o.tag == .native_fn) {
            const native = o.as(types.NativeFn);
            native.profile_calls = 0;
            native.profile_time_ns = 0;
            native.profile_alloc_bytes = 0;
        }
        obj = o.next;
    }
}

fn fmtMs(buf: []u8, ns: u64) []const u8 {
    if (ns == 0) return "       -";
    const ms_whole = ns / 1_000_000;
    const ms_frac = (ns % 1_000_000) / 100_000;
    return std.fmt.bufPrint(buf, "{d:>6}.{d}", .{ ms_whole, ms_frac }) catch "       ?";
}

fn fmtKb(buf: []u8, bytes: u64) []const u8 {
    if (bytes == 0) return "      -";
    const kb = bytes / 1024;
    if (kb > 0) {
        return std.fmt.bufPrint(buf, "{d:>6}", .{kb}) catch "      ?";
    }
    return std.fmt.bufPrint(buf, "   <1", .{}) catch "      ?";
}

pub fn printProfileReport(gc: *memory.GC) void {
    const Entry = struct {
        name: []const u8,
        source: ?[]const u8,
        line: u32,
        instrs: u64,
        calls: u64,
        self_ns: u64,
        total_ns: u64,
        alloc_bytes: u64,
    };

    var entries: [256]Entry = undefined;
    var count: usize = 0;
    var total_instrs: u64 = 0;
    var total_calls: u64 = 0;

    var obj = gc.objects;
    while (obj) |o| {
        if (o.tag == .function) {
            const func = o.as(types.Function);
            if (func.profile_instrs > 0 or func.profile_calls > 0) {
                total_instrs += func.profile_instrs;
                total_calls += func.profile_calls;
                if (count < 256) {
                    entries[count] = .{
                        .name = func.name orelse "(lambda)",
                        .source = func.source_name,
                        .line = func.source_line,
                        .instrs = func.profile_instrs,
                        .calls = func.profile_calls,
                        .self_ns = func.profile_time_ns,
                        .total_ns = func.profile_inclusive_ns,
                        .alloc_bytes = func.profile_alloc_bytes,
                    };
                    count += 1;
                }
            }
        } else if (o.tag == .native_fn) {
            const native = o.as(types.NativeFn);
            if (native.profile_calls > 0) {
                total_calls += native.profile_calls;
                if (count < 256) {
                    entries[count] = .{
                        .name = native.name,
                        .source = null,
                        .line = 0,
                        .instrs = 0,
                        .calls = native.profile_calls,
                        .self_ns = native.profile_time_ns,
                        .total_ns = native.profile_time_ns,
                        .alloc_bytes = native.profile_alloc_bytes,
                    };
                    count += 1;
                }
            }
        }
        obj = o.next;
    }

    if (count == 0) return;

    std.mem.sortUnstable(Entry, entries[0..count], {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            if (a.self_ns != b.self_ns) return a.self_ns > b.self_ns;
            if (a.instrs != b.instrs) return a.instrs > b.instrs;
            return a.calls > b.calls;
        }
    }.lessThan);

    var buf: [256]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "\nProfile ({d} instructions, {d} calls):\n", .{ total_instrs, total_calls }) catch return;
    writeStderr(header);
    writeStderr("  Self ms  Total ms    Calls  Alloc KB  Function\n");

    const limit = @min(count, 20);
    for (entries[0..limit]) |e| {
        var line: [512]u8 = undefined;
        var loc_buf: [128]u8 = undefined;
        const location: []const u8 = if (e.source) |src|
            std.fmt.bufPrint(&loc_buf, " ({s}:{d})", .{ src, e.line }) catch ""
        else
            " (built-in)";

        var self_buf: [16]u8 = undefined;
        var total_buf: [16]u8 = undefined;
        var alloc_buf: [16]u8 = undefined;
        const self_ms = fmtMs(&self_buf, e.self_ns);
        const total_ms = fmtMs(&total_buf, e.total_ns);
        const alloc_kb = fmtKb(&alloc_buf, e.alloc_bytes);

        const s = std.fmt.bufPrint(&line, "  {s}  {s} {d:>8}  {s}    {s}{s}\n", .{
            self_ms, total_ms, e.calls, alloc_kb, e.name, location,
        }) catch continue;
        writeStderr(s);
    }
}

const DefineMap = struct {
    names: [128][]const u8,
    lines: [128]u32,
    count: usize,

    fn lookup(self: *const DefineMap, name: []const u8) ?u32 {
        for (self.names[0..self.count], self.lines[0..self.count]) |n, l| {
            if (std.mem.eql(u8, n, name)) return l;
        }
        return null;
    }
};

fn scanDefines(source: []const u8) DefineMap {
    var map = DefineMap{ .names = undefined, .lines = undefined, .count = 0 };
    var line_num: u32 = 1;
    var i: usize = 0;
    while (i < source.len) {
        // Find start of line content (skip whitespace)
        const line_start = i;
        while (i < source.len and source[i] != '\n') : (i += 1) {}
        const line = source[line_start..i];
        if (i < source.len) i += 1; // skip newline

        // Look for (define at start of meaningful content
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "(define ")) {
            const after_define = trimmed[8..];
            if (map.count < 128) {
                if (after_define.len > 0 and after_define[0] == '(') {
                    // (define (name args...) body) form
                    if (extractName(after_define[1..])) |name| {
                        map.names[map.count] = name;
                        map.lines[map.count] = line_num;
                        map.count += 1;
                    }
                } else {
                    // (define name value) form
                    if (extractName(after_define)) |name| {
                        map.names[map.count] = name;
                        map.lines[map.count] = line_num;
                        map.count += 1;
                    }
                }
            }
        }
        line_num += 1;
    }
    return map;
}

fn extractName(s: []const u8) ?[]const u8 {
    var end: usize = 0;
    while (end < s.len and s[end] != ' ' and s[end] != ')' and s[end] != '\n' and s[end] != '\t') : (end += 1) {}
    if (end == 0) return null;
    return s[0..end];
}

fn resolveSldPath(allocator: std.mem.Allocator, rel_path: []const u8, lib_paths: []const []const u8) ?[]u8 {
    var bases: [18][]const u8 = undefined;
    bases[0] = "";
    bases[1] = "lib/";
    var base_count: usize = 2;
    for (lib_paths) |lp| {
        if (base_count >= 18) break;
        bases[base_count] = lp;
        base_count += 1;
    }

    for (bases[0..base_count]) |base| {
        var full: [513]u8 = undefined;
        var len: usize = 0;
        if (base.len > 0) {
            if (base.len + 1 + rel_path.len >= full.len) continue;
            @memcpy(full[0..base.len], base);
            len = base.len;
            if (base[base.len - 1] != '/') {
                full[len] = '/';
                len += 1;
            }
        }
        if (len + rel_path.len >= full.len) continue;
        @memcpy(full[len..][0..rel_path.len], rel_path);
        len += rel_path.len;
        const path_z = allocator.dupeZ(u8, full[0..len]) catch continue;
        const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{}, 0) catch {
            allocator.free(path_z);
            continue;
        };
        _ = std.posix.system.close(fd);
        allocator.free(path_z);
        return allocator.dupe(u8, full[0..len]) catch null;
    }
    return null;
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ?[]u8 {
    const path_z = allocator.dupeZ(u8, path) catch return null;
    defer allocator.free(path_z);
    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{}, 0) catch return null;
    defer _ = std.posix.system.close(fd);

    var result: std.ArrayList(u8) = .empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &tmp) catch break;
        if (n == 0) break;
        result.appendSlice(allocator, tmp[0..n]) catch break;
    }
    return result.toOwnedSlice(allocator) catch null;
}

fn xmlEscape(out: *std.ArrayList(u8), allocator: std.mem.Allocator, s: []const u8) void {
    for (s) |c| {
        switch (c) {
            '&' => out.appendSlice(allocator, "&amp;") catch {},
            '<' => out.appendSlice(allocator, "&lt;") catch {},
            '>' => out.appendSlice(allocator, "&gt;") catch {},
            '"' => out.appendSlice(allocator, "&quot;") catch {},
            else => out.append(allocator, c) catch {},
        }
    }
}

fn xmlAppend(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
    out.appendSlice(allocator, s) catch {};
}

pub fn writeCoverageXml(vm: *vm_mod.VM, path: []const u8) void {
    const allocator = vm.gc.allocator;
    var xml: std.ArrayList(u8) = .empty;
    defer xml.deinit(allocator);

    var total_procs: usize = 0;
    var total_called: usize = 0;

    const ProcEntry = struct { name: []const u8, hits: u64 };
    const PkgEntry = struct {
        lib_name: []const u8,
        procs: [128]ProcEntry,
        proc_count: usize,
        called: usize,
        total: usize,
    };

    var pkgs: [64]PkgEntry = undefined;
    var pkg_count: usize = 0;

    var lib_it = vm.libraries.libraries.iterator();
    while (lib_it.next()) |entry| {
        const lib = entry.value_ptr;
        if (lib.owned_name == null) continue;

        var pkg = PkgEntry{
            .lib_name = lib.name,
            .procs = undefined,
            .proc_count = 0,
            .called = 0,
            .total = 0,
        };

        var exp_it = lib.exports.iterator();
        while (exp_it.next()) |exp| {
            const count = getCallCount(exp.value_ptr.*) orelse continue;
            if (pkg.proc_count < 128) {
                pkg.procs[pkg.proc_count] = .{ .name = exp.key_ptr.*, .hits = count };
                pkg.proc_count += 1;
            }
            pkg.total += 1;
            if (count > 0) pkg.called += 1;
        }

        if (pkg.total == 0) continue;
        total_procs += pkg.total;
        total_called += pkg.called;

        if (pkg_count < 64) {
            pkgs[pkg_count] = pkg;
            pkg_count += 1;
        }
    }

    const overall_rate = if (total_procs > 0)
        @as(f64, @floatFromInt(total_called)) / @as(f64, @floatFromInt(total_procs))
    else
        1.0;

    xml.appendSlice(allocator, "<?xml version=\"1.0\" ?>\n") catch {};
    xmlAppend(&xml, allocator, "<coverage line-rate=\"{d:.4}\" branch-rate=\"0\" version=\"kaappi\" timestamp=\"0\" lines-covered=\"{d}\" lines-valid=\"{d}\">\n", .{ overall_rate, total_called, total_procs });
    xml.appendSlice(allocator, "  <packages>\n") catch {};

    for (pkgs[0..pkg_count]) |pkg| {
        const pkg_rate = if (pkg.total > 0)
            @as(f64, @floatFromInt(pkg.called)) / @as(f64, @floatFromInt(pkg.total))
        else
            1.0;

        // Convert "kaappi.json" → "lib/kaappi/json.sld"
        var file_buf: [256]u8 = undefined;
        var file_len: usize = 0;
        const prefix = "lib/";
        @memcpy(file_buf[0..prefix.len], prefix);
        file_len = prefix.len;
        for (pkg.lib_name) |c| {
            if (file_len >= file_buf.len - 5) break;
            file_buf[file_len] = if (c == '.') '/' else c;
            file_len += 1;
        }
        const suffix = ".sld";
        @memcpy(file_buf[file_len..][0..suffix.len], suffix);
        file_len += suffix.len;
        const filename = file_buf[0..file_len];

        xml.appendSlice(allocator, "    <package name=\"") catch {};
        xmlEscape(&xml, allocator, pkg.lib_name);
        xmlAppend(&xml, allocator, "\" line-rate=\"{d:.4}\" branch-rate=\"0\">\n", .{pkg_rate});
        xml.appendSlice(allocator, "      <classes>\n") catch {};
        xml.appendSlice(allocator, "        <class name=\"") catch {};
        xmlEscape(&xml, allocator, pkg.lib_name);
        xml.appendSlice(allocator, "\" filename=\"") catch {};
        xmlEscape(&xml, allocator, filename);
        xmlAppend(&xml, allocator, "\" line-rate=\"{d:.4}\" branch-rate=\"0\">\n", .{pkg_rate});
        xml.appendSlice(allocator, "          <lines>\n") catch {};

        // Try to resolve real line numbers from the .sld source
        // Build relative path without "lib/" prefix: "kaappi.json" → "kaappi/json.sld"
        var rel_buf: [256]u8 = undefined;
        var rel_len: usize = 0;
        for (pkg.lib_name) |c| {
            if (rel_len >= rel_buf.len - 5) break;
            rel_buf[rel_len] = if (c == '.') '/' else c;
            rel_len += 1;
        }
        @memcpy(rel_buf[rel_len..][0..4], ".sld");
        rel_len += 4;
        const rel_path = rel_buf[0..rel_len];

        var define_map: ?DefineMap = null;
        var sld_source: ?[]u8 = null;
        {
            const resolved = resolveSldPath(allocator, rel_path, vm.lib_paths);
            if (resolved) |sld_path| {
                defer allocator.free(sld_path);
                sld_source = readFile(allocator, sld_path);
                if (sld_source) |source| {
                    define_map = scanDefines(source);
                }
            }
        }

        for (pkg.procs[0..pkg.proc_count], 1..) |proc, fallback_num| {
            const line_num: u32 = if (define_map) |*dm| dm.lookup(proc.name) orelse @intCast(fallback_num) else @intCast(fallback_num);
            xml.appendSlice(allocator, "            <line number=\"") catch {};
            xmlAppend(&xml, allocator, "{d}", .{line_num});
            xml.appendSlice(allocator, "\" hits=\"") catch {};
            xmlAppend(&xml, allocator, "{d}", .{proc.hits});
            xml.appendSlice(allocator, "\" name=\"") catch {};
            xmlEscape(&xml, allocator, proc.name);
            xml.appendSlice(allocator, "\"/>\n") catch {};
        }

        xml.appendSlice(allocator, "          </lines>\n") catch {};
        xml.appendSlice(allocator, "        </class>\n") catch {};
        xml.appendSlice(allocator, "      </classes>\n") catch {};
        xml.appendSlice(allocator, "    </package>\n") catch {};
        if (sld_source) |s| allocator.free(s);
    }

    xml.appendSlice(allocator, "  </packages>\n") catch {};
    xml.appendSlice(allocator, "</coverage>\n") catch {};

    // Write to file
    const fd = std.posix.openat(std.posix.AT.FDCWD, @ptrCast(path), .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch {
        writeStderr("error: could not open coverage XML output file\n");
        return;
    };
    defer _ = std.posix.system.close(fd);

    var written: usize = 0;
    while (written < xml.items.len) {
        const result = std.posix.system.write(fd, xml.items.ptr + written, xml.items.len - written);
        if (result <= 0) break;
        written += @as(usize, @intCast(result));
    }
}

fn getCallCount(val: types.Value) ?u64 {
    if (!types.isPointer(val)) return null;
    const obj = types.toObject(val);
    return switch (obj.tag) {
        .closure => obj.as(types.Closure).func.profile_calls,
        .native_fn => obj.as(types.NativeFn).profile_calls,
        else => null,
    };
}

pub fn printCoverageReport(vm: *vm_mod.VM) void {
    var buf: [512]u8 = undefined;
    var total_procs: usize = 0;
    var total_called: usize = 0;
    var any_lib = false;

    const LibEntry = struct {
        name: []const u8,
        procs: usize,
        called: usize,
        uncalled: [128][]const u8,
        uncalled_count: usize,
    };

    var libs: [64]LibEntry = undefined;
    var lib_count: usize = 0;

    var lib_it = vm.libraries.libraries.iterator();
    while (lib_it.next()) |entry| {
        const lib = entry.value_ptr;
        if (lib.owned_name == null) continue;

        any_lib = true;
        var procs: usize = 0;
        var called: usize = 0;
        var uncalled: [128][]const u8 = undefined;
        var uncalled_count: usize = 0;

        var exp_it = lib.exports.iterator();
        while (exp_it.next()) |exp| {
            const count = getCallCount(exp.value_ptr.*) orelse continue;
            procs += 1;
            if (count > 0) {
                called += 1;
            } else {
                if (uncalled_count < 128) {
                    uncalled[uncalled_count] = exp.key_ptr.*;
                    uncalled_count += 1;
                }
            }
        }

        if (procs == 0) continue;

        total_procs += procs;
        total_called += called;

        if (lib_count < 64) {
            libs[lib_count] = .{
                .name = lib.name,
                .procs = procs,
                .called = called,
                .uncalled = uncalled,
                .uncalled_count = uncalled_count,
            };
            lib_count += 1;
        }
    }

    if (!any_lib) {
        writeStderr("\nCoverage: no user libraries loaded\n");
        return;
    }

    writeStderr("\nCoverage:\n");

    for (libs[0..lib_count]) |lib| {
        const pct: f64 = if (lib.procs > 0)
            @as(f64, @floatFromInt(lib.called)) / @as(f64, @floatFromInt(lib.procs)) * 100.0
        else
            100.0;

        // Format library name: "kaappi.json" → "(kaappi json)"
        var name_buf: [128]u8 = undefined;
        var name_len: usize = 0;
        name_buf[0] = '(';
        name_len = 1;
        for (lib.name) |c| {
            if (name_len >= name_buf.len - 1) break;
            name_buf[name_len] = if (c == '.') ' ' else c;
            name_len += 1;
        }
        if (name_len < name_buf.len) {
            name_buf[name_len] = ')';
            name_len += 1;
        }
        const display_name = name_buf[0..name_len];

        const line = std.fmt.bufPrint(&buf, "  {s: <30} {d}/{d}  {d:.1}%\n", .{
            display_name, lib.called, lib.procs, pct,
        }) catch continue;
        writeStderr(line);

        if (lib.uncalled_count > 0) {
            writeStderr("    uncalled:");
            for (lib.uncalled[0..lib.uncalled_count]) |name| {
                writeStderr(" ");
                writeStderr(name);
            }
            writeStderr("\n");
        }
    }

    if (total_procs > 0) {
        const overall_pct = @as(f64, @floatFromInt(total_called)) / @as(f64, @floatFromInt(total_procs)) * 100.0;
        const summary = std.fmt.bufPrint(&buf, "\n  Overall: {d}/{d} procedures covered ({d:.1}%)\n", .{
            total_called, total_procs, overall_pct,
        }) catch return;
        writeStderr(summary);
    }
}

pub fn writeProfileJson(gc: *memory.GC, path: []const u8) void {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch return;
    defer _ = std.posix.system.close(fd);

    writeToFd(fd, "[");
    var first = true;
    var obj = gc.objects;
    while (obj) |o| {
        if (o.tag == .function) {
            const func = o.as(types.Function);
            if (func.profile_calls > 0) {
                if (!first) writeToFd(fd, ",");
                first = false;
                var buf: [512]u8 = undefined;
                const s = std.fmt.bufPrint(&buf,
                    \\{{"name":"{s}","source":"{s}","line":{d},"calls":{d},"self_ns":{d},"total_ns":{d},"alloc_bytes":{d}}}
                , .{
                    func.name orelse "(lambda)",
                    func.source_name orelse "?",
                    func.source_line,
                    func.profile_calls,
                    func.profile_time_ns,
                    func.profile_inclusive_ns,
                    func.profile_alloc_bytes,
                }) catch continue;
                writeToFd(fd, s);
            }
        } else if (o.tag == .native_fn) {
            const native = o.as(types.NativeFn);
            if (native.profile_calls > 0) {
                if (!first) writeToFd(fd, ",");
                first = false;
                var buf: [512]u8 = undefined;
                const s = std.fmt.bufPrint(&buf,
                    \\{{"name":"{s}","source":"built-in","line":0,"calls":{d},"self_ns":{d},"total_ns":{d},"alloc_bytes":{d}}}
                , .{
                    native.name,
                    native.profile_calls,
                    native.profile_time_ns,
                    native.profile_time_ns,
                    native.profile_alloc_bytes,
                }) catch continue;
                writeToFd(fd, s);
            }
        }
        obj = o.next;
    }
    writeToFd(fd, "]\n");
}
