const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const CallFrame = vm_mod.CallFrame;

fn writeStderr(bytes: []const u8) void {
    vm_mod.writeStderr(bytes);
}

pub fn shouldDebugPause(vm: *VM, frame: *CallFrame) bool {
    _ = frame;
    switch (vm.step_mode) {
        .step => return true,
        .next => return vm.frame_count <= vm.step_frame,
        .step_out => return vm.frame_count < vm.step_frame,
        .continue_to_break => {
            if (vm.watch_count > 0) return checkWatches(vm);
            return false;
        },
        .none => return false,
    }
}

fn checkWatches(vm: *VM) bool {
    if (vm.frame_count == 0) return false;
    const frame = vm.frames[vm.frame_count - 1];
    const cls = frame.closure orelse return false;
    const func = cls.func;
    const printer = @import("printer.zig");

    for (vm.watches[0..vm.watch_count]) |*w| {
        for (func.debug_locals) |local| {
            if (std.mem.eql(u8, local.name, w.name)) {
                const val = vm.registers[frame.base + local.slot];
                if (val != w.last_value) {
                    w.last_value = val;
                    writeStderr("Watch: ");
                    writeStderr(w.name);
                    writeStderr(" = ");
                    const s = printer.valueToString(vm.gc.allocator, val, .write) catch "?";
                    defer vm.gc.allocator.free(s);
                    writeStderr(s);
                    writeStderr("\n");
                    return true;
                }
            }
        }
    }
    return false;
}

pub fn debugPause(vm: *VM, frame: *CallFrame) !void {
    vm.inspect_frame = if (vm.frame_count > 0) vm.frame_count - 1 else 0;

    if (frame.closure) |cls| {
        const func = cls.func;
        writeStderr("Break");
        if (func.name) |name| {
            writeStderr(" at ");
            writeStderr(name);
        }
        if (func.source_name) |src| {
            writeStderr(" (");
            writeStderr(src);
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, ":{d}", .{func.source_line}) catch "";
            writeStderr(s);
            writeStderr(")");
        }
        writeStderr("\n");
    }

    var cmd_buf: [256]u8 = undefined;
    while (true) {
        writeStderr("debug> ");
        var i: usize = 0;
        while (i < cmd_buf.len) {
            const result = std.posix.system.read(0, cmd_buf[i .. i + 1].ptr, 1);
            if (result <= 0) {
                vm.debug_mode = false;
                vm.step_mode = .none;
                return;
            }
            if (cmd_buf[i] == '\n') break;
            i += 1;
        }
        const cmd = std.mem.trim(u8, cmd_buf[0..i], " \t\r");

        if (cmd.len == 0) continue;

        if (std.mem.eql(u8, cmd, "step") or std.mem.eql(u8, cmd, "s")) {
            vm.step_mode = .step;
            return;
        }
        if (std.mem.eql(u8, cmd, "next") or std.mem.eql(u8, cmd, "n")) {
            vm.step_mode = .next;
            vm.step_frame = vm.frame_count;
            return;
        }
        if (std.mem.eql(u8, cmd, "finish") or std.mem.eql(u8, cmd, "out")) {
            vm.step_mode = .step_out;
            vm.step_frame = vm.frame_count;
            return;
        }
        if (std.mem.eql(u8, cmd, "continue") or std.mem.eql(u8, cmd, "c")) {
            vm.step_mode = .continue_to_break;
            return;
        }
        if (std.mem.eql(u8, cmd, "locals") or std.mem.eql(u8, cmd, "l")) {
            printLocals(vm, vm.inspect_frame, vm.gc.allocator);
            continue;
        }
        if (std.mem.eql(u8, cmd, "backtrace") or std.mem.eql(u8, cmd, "bt")) {
            printBacktrace(vm);
            continue;
        }
        if (std.mem.eql(u8, cmd, "up")) {
            if (vm.inspect_frame + 1 < vm.frame_count) {
                vm.inspect_frame += 1;
                printFrameInfo(vm, vm.inspect_frame);
            } else {
                writeStderr("Already at top of stack\n");
            }
            continue;
        }
        if (std.mem.eql(u8, cmd, "down")) {
            if (vm.inspect_frame > 0) {
                vm.inspect_frame -= 1;
                printFrameInfo(vm, vm.inspect_frame);
            } else {
                writeStderr("Already at bottom of stack\n");
            }
            continue;
        }
        if (std.mem.startsWith(u8, cmd, "watch ")) {
            const var_name = std.mem.trim(u8, cmd[6..], " ");
            if (var_name.len > 0 and vm.watch_count < 16) {
                vm.watches[vm.watch_count] = .{ .name = var_name };
                vm.watch_count += 1;
                writeStderr("Watching ");
                writeStderr(var_name);
                writeStderr("\n");
            }
            continue;
        }
        if (std.mem.startsWith(u8, cmd, "unwatch ")) {
            const var_name = std.mem.trim(u8, cmd[8..], " ");
            var found = false;
            var j: usize = 0;
            while (j < vm.watch_count) {
                if (std.mem.eql(u8, vm.watches[j].name, var_name)) {
                    vm.watch_count -= 1;
                    if (j < vm.watch_count) {
                        vm.watches[j] = vm.watches[vm.watch_count];
                    }
                    found = true;
                    break;
                }
                j += 1;
            }
            if (found) {
                writeStderr("Unwatched ");
                writeStderr(var_name);
                writeStderr("\n");
            } else {
                writeStderr("No watch on ");
                writeStderr(var_name);
                writeStderr("\n");
            }
            continue;
        }
        if (std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "q")) {
            vm.debug_mode = false;
            vm.step_mode = .none;
            return;
        }
        writeStderr("Commands: step(s), next(n), finish/out, continue(c),\n");
        writeStderr("          locals(l), backtrace(bt), up, down,\n");
        writeStderr("          watch <var>, unwatch <var>, quit(q)\n");
    }
}

fn printLocals(vm: *VM, frame_idx: usize, allocator: std.mem.Allocator) void {
    if (frame_idx >= vm.frame_count) return;
    const f = vm.frames[frame_idx];
    if (f.closure) |cls| {
        const func = cls.func;
        const printer = @import("printer.zig");
        for (func.debug_locals) |local| {
            writeStderr("  ");
            writeStderr(local.name);
            writeStderr(" = ");
            const val = vm.registers[f.base + local.slot];
            const s = printer.valueToString(allocator, val, .write) catch continue;
            defer allocator.free(s);
            writeStderr(s);
            writeStderr("\n");
        }
        if (func.debug_locals.len == 0) {
            writeStderr("  (no locals)\n");
        }
    }
}

fn printFrameInfo(vm: *VM, frame_idx: usize) void {
    if (frame_idx >= vm.frame_count) return;
    const f = vm.frames[frame_idx];
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "[{d}] ", .{frame_idx}) catch "";
    writeStderr(s);
    if (f.closure) |cls| {
        if (cls.func.name) |name| {
            writeStderr(name);
        } else {
            writeStderr("<lambda>");
        }
    } else {
        writeStderr("<native>");
    }
    writeStderr("\n");
}

fn printBacktrace(vm: *VM) void {
    var i: usize = vm.frame_count;
    while (i > 0) {
        i -= 1;
        const f = vm.frames[i];
        const marker: []const u8 = if (i == vm.inspect_frame) "> " else "  ";
        writeStderr(marker);
        var buf: [32]u8 = undefined;
        const idx = std.fmt.bufPrint(&buf, "[{d}] ", .{i}) catch "";
        writeStderr(idx);
        if (f.closure) |cls| {
            if (cls.func.name) |name| {
                writeStderr(name);
            } else {
                writeStderr("<lambda>");
            }
        } else {
            writeStderr("<native>");
        }
        writeStderr("\n");
    }
}
