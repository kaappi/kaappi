const std = @import("std");
pub const types = @import("types.zig");
pub const memory = @import("memory.zig");
pub const vm_mod = @import("vm.zig");
pub const library_mod = @import("library.zig");

fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        const written: usize = @intCast(result);
        if (written == 0) break;
        total += written;
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
