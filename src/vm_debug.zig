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
    return switch (vm.step_mode) {
        .step => true,
        .next => vm.frame_count <= vm.step_frame,
        .continue_to_break => false,
        .none => false,
    };
}

pub fn debugPause(vm: *VM, frame: *CallFrame) !void {
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
        if (std.mem.eql(u8, cmd, "continue") or std.mem.eql(u8, cmd, "c")) {
            vm.step_mode = .continue_to_break;
            return;
        }
        if (std.mem.eql(u8, cmd, "locals") or std.mem.eql(u8, cmd, "l")) {
            printLocals(vm, frame, vm.gc.allocator);
            continue;
        }
        if (std.mem.eql(u8, cmd, "backtrace") or std.mem.eql(u8, cmd, "bt")) {
            printBacktrace(vm);
            continue;
        }
        if (std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "q")) {
            vm.debug_mode = false;
            vm.step_mode = .none;
            return;
        }
        writeStderr("Commands: step(s), next(n), continue(c), locals(l), backtrace(bt), quit(q)\n");
    }
}

fn printLocals(vm: *VM, frame: *CallFrame, allocator: std.mem.Allocator) void {
    if (frame.closure) |cls| {
        const func = cls.func;
        const printer = @import("printer.zig");
        for (func.debug_locals) |local| {
            writeStderr("  ");
            writeStderr(local.name);
            writeStderr(" = ");
            const val = vm.registers[frame.base + local.slot];
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

fn printBacktrace(vm: *VM) void {
    var i: usize = vm.frame_count;
    while (i > 0) {
        i -= 1;
        const f = vm.frames[i];
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
