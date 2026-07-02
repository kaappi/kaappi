const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const compiler = @import("compiler.zig");
const reader = @import("reader.zig");
const printer = @import("printer.zig");
const vm_library = @import("vm_library.zig");
const reporting = @import("reporting.zig");
const expander = @import("expander.zig");
const ln = if (is_wasm) struct {} else @import("linenoise.zig");

const version = @import("main.zig").version;

var repl_vm: ?*vm_mod.VM = null;

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

fn isIdentBreak(c: u8) bool {
    return switch (c) {
        '(', ')', '\'', '`', ',', '"', ';', '#', '[', ']', ' ', '\t', '\n', '\r' => true,
        else => false,
    };
}

fn completionCallback(buf: [*c]const u8, lc: [*c]ln.c.linenoiseCompletions) callconv(.c) void {
    const vm = repl_vm orelse return;
    const b: ?[*:0]const u8 = @ptrCast(buf);
    const line = if (b) |bp| std.mem.span(bp) else return;
    if (line.len == 0) return;

    if (line[0] == ',') {
        const commands = [_][*:0]const u8{
            ",time ",  ",type ",       ",describe ", ",apropos ",
            ",env ",   ",profile ",    ",expand ",   ",gc",
            ",break ", ",breakpoints", ",delete ",   ",step ",
            ",help",   ",quit",        ",exit",      ",version",
            ",load ",  ",import ",     ",dis ",      ",condition ",
        };
        for (&commands) |cmd| {
            if (std.mem.startsWith(u8, std.mem.span(cmd), line)) {
                ln.addCompletion(lc, cmd);
            }
        }
        return;
    }

    var ident_start = line.len;
    while (ident_start > 0 and !isIdentBreak(line[ident_start - 1])) {
        ident_start -= 1;
    }
    const ident_prefix = line[ident_start..];
    if (ident_prefix.len == 0) return;
    const line_prefix = line[0..ident_start];

    var it = vm.globals.keyIterator();
    while (it.next()) |key| {
        if (std.mem.startsWith(u8, key.*, ident_prefix)) {
            var completion_buf: [1024:0]u8 = undefined;
            const total_len = line_prefix.len + key.*.len;
            if (total_len >= completion_buf.len) continue;
            @memcpy(completion_buf[0..line_prefix.len], line_prefix);
            @memcpy(completion_buf[line_prefix.len..][0..key.*.len], key.*);
            completion_buf[total_len] = 0;
            ln.addCompletion(lc, &completion_buf);
        }
    }
}

const ANSI_RESET = "\x1b[0m";
const ANSI_KEYWORD = "\x1b[35m"; // magenta
const ANSI_STRING = "\x1b[32m"; // green
const ANSI_NUMBER = "\x1b[33m"; // yellow
const ANSI_COMMENT = "\x1b[90m"; // bright black (gray)
const ANSI_BOOLEAN = "\x1b[36m"; // cyan
const ANSI_PAREN = "\x1b[90m"; // gray

fn isSchemeKeyword(word: []const u8) bool {
    const keywords = [_][]const u8{
        "define",        "lambda",       "if",             "cond",
        "let",           "let*",         "letrec",         "letrec*",
        "begin",         "set!",         "and",            "or",
        "when",          "unless",       "case",           "do",
        "define-syntax", "syntax-rules", "quote",          "quasiquote",
        "unquote",       "import",       "define-library", "define-record-type",
        "guard",         "delay",        "delay-force",    "parameterize",
        "include",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, word, kw)) return true;
    }
    return false;
}

fn isDelimiter(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '(' or ch == ')' or ch == '"' or ch == ';' or ch == '\n' or ch == '\r';
}

fn highlightCallback(buf: [*c]const u8, len: usize, out_len: [*c]usize) callconv(.c) [*c]u8 {
    if (len == 0) {
        out_len.* = 0;
        return null;
    }
    const input = buf[0..len];

    var result: std.ArrayList(u8) = .empty;
    const allocator = std.heap.c_allocator;

    var i: usize = 0;
    while (i < input.len) {
        const ch = input[i];

        if (ch == ';') {
            result.appendSlice(allocator, ANSI_COMMENT) catch return null;
            while (i < input.len and input[i] != '\n') : (i += 1) {
                result.append(allocator, input[i]) catch return null;
            }
            result.appendSlice(allocator, ANSI_RESET) catch return null;
            continue;
        }

        if (ch == '#' and i + 1 < input.len and input[i + 1] == '|') {
            result.appendSlice(allocator, ANSI_COMMENT) catch return null;
            result.append(allocator, '#') catch return null;
            result.append(allocator, '|') catch return null;
            i += 2;
            var depth: u32 = 1;
            while (i < input.len and depth > 0) {
                if (input[i] == '#' and i + 1 < input.len and input[i + 1] == '|') {
                    depth += 1;
                    result.appendSlice(allocator, "#|") catch return null;
                    i += 2;
                } else if (input[i] == '|' and i + 1 < input.len and input[i + 1] == '#') {
                    depth -= 1;
                    result.appendSlice(allocator, "|#") catch return null;
                    i += 2;
                } else {
                    result.append(allocator, input[i]) catch return null;
                    i += 1;
                }
            }
            result.appendSlice(allocator, ANSI_RESET) catch return null;
            continue;
        }

        if (ch == '"') {
            result.appendSlice(allocator, ANSI_STRING) catch return null;
            result.append(allocator, '"') catch return null;
            i += 1;
            while (i < input.len) {
                result.append(allocator, input[i]) catch return null;
                if (input[i] == '\\' and i + 1 < input.len) {
                    i += 1;
                    result.append(allocator, input[i]) catch return null;
                } else if (input[i] == '"') {
                    i += 1;
                    break;
                }
                i += 1;
            }
            result.appendSlice(allocator, ANSI_RESET) catch return null;
            continue;
        }

        if (ch == '(' or ch == ')') {
            result.appendSlice(allocator, ANSI_PAREN) catch return null;
            result.append(allocator, ch) catch return null;
            result.appendSlice(allocator, ANSI_RESET) catch return null;
            i += 1;
            continue;
        }

        if (ch == '#' and i + 1 < input.len and input[i + 1] == '\\') {
            result.appendSlice(allocator, ANSI_NUMBER) catch return null;
            result.append(allocator, '#') catch return null;
            result.append(allocator, '\\') catch return null;
            i += 2;
            if (i < input.len) {
                const first = input[i];
                if ((first >= 'a' and first <= 'z') or (first >= 'A' and first <= 'Z')) {
                    while (i < input.len and ((input[i] >= 'a' and input[i] <= 'z') or (input[i] >= 'A' and input[i] <= 'Z'))) {
                        result.append(allocator, input[i]) catch return null;
                        i += 1;
                    }
                } else {
                    result.append(allocator, first) catch return null;
                    i += 1;
                }
            }
            result.appendSlice(allocator, ANSI_RESET) catch return null;
            continue;
        }

        if (ch == '#' and i + 1 < input.len and (input[i + 1] == 't' or input[i + 1] == 'f')) {
            const is_bool = (i + 2 >= input.len or isDelimiter(input[i + 2]));
            if (is_bool) {
                result.appendSlice(allocator, ANSI_BOOLEAN) catch return null;
                result.append(allocator, '#') catch return null;
                result.append(allocator, input[i + 1]) catch return null;
                result.appendSlice(allocator, ANSI_RESET) catch return null;
                i += 2;
                continue;
            }
        }

        if (ch == '\'' or ch == '`' or ch == ',') {
            result.appendSlice(allocator, ANSI_KEYWORD) catch return null;
            result.append(allocator, ch) catch return null;
            result.appendSlice(allocator, ANSI_RESET) catch return null;
            i += 1;
            continue;
        }

        if (!isDelimiter(ch)) {
            const start = i;
            while (i < input.len and !isDelimiter(input[i])) : (i += 1) {}
            const word = input[start..i];

            if (isSchemeKeyword(word)) {
                result.appendSlice(allocator, ANSI_KEYWORD) catch return null;
                result.appendSlice(allocator, word) catch return null;
                result.appendSlice(allocator, ANSI_RESET) catch return null;
            } else if (word.len > 0 and (std.ascii.isDigit(word[0]) or
                (word[0] == '-' and word.len > 1 and std.ascii.isDigit(word[1])) or
                (word[0] == '+' and word.len > 1 and std.ascii.isDigit(word[1]))))
            {
                result.appendSlice(allocator, ANSI_NUMBER) catch return null;
                result.appendSlice(allocator, word) catch return null;
                result.appendSlice(allocator, ANSI_RESET) catch return null;
            } else {
                result.appendSlice(allocator, word) catch return null;
            }
            continue;
        }

        result.append(allocator, ch) catch return null;
        i += 1;
    }

    out_len.* = result.items.len;
    const owned = result.toOwnedSlice(allocator) catch return null;
    return @ptrCast(owned.ptr);
}

fn parenDepth(src: []const u8) i32 {
    var depth: i32 = 0;
    var in_string = false;
    var in_escape = false;
    var in_line_comment = false;
    var block_comment_depth: i32 = 0;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        const ch = src[i];
        if (in_line_comment) {
            if (ch == '\n') in_line_comment = false;
            continue;
        }
        if (block_comment_depth > 0) {
            if (ch == '#' and i + 1 < src.len and src[i + 1] == '|') {
                block_comment_depth += 1;
                i += 1;
            } else if (ch == '|' and i + 1 < src.len and src[i + 1] == '#') {
                block_comment_depth -= 1;
                i += 1;
            }
            continue;
        }
        if (in_escape) {
            in_escape = false;
            continue;
        }
        if (in_string) {
            if (ch == '\\') in_escape = true else if (ch == '"') in_string = false;
            continue;
        }
        if (ch == '#' and i + 1 < src.len and src[i + 1] == '|') {
            block_comment_depth += 1;
            i += 1;
            continue;
        }
        // Datum comment: #; — skip the next datum for paren counting
        if (ch == '#' and i + 1 < src.len and src[i + 1] == ';') {
            i += 2;
            // Skip whitespace
            while (i < src.len and (src[i] == ' ' or src[i] == '\t' or src[i] == '\n' or src[i] == '\r')) : (i += 1) {}
            if (i >= src.len) {
                depth += 1;
                continue;
            }
            if (src[i] == '(' or src[i] == '[') {
                var datum_depth: i32 = 1;
                i += 1;
                var dc_in_string = false;
                var dc_escape = false;
                while (i < src.len and datum_depth > 0) {
                    if (dc_escape) {
                        dc_escape = false;
                        i += 1;
                        continue;
                    }
                    if (dc_in_string) {
                        if (src[i] == '\\') dc_escape = true else if (src[i] == '"') dc_in_string = false;
                        i += 1;
                        continue;
                    }
                    if (src[i] == '"') {
                        dc_in_string = true;
                    } else if (src[i] == '(' or src[i] == '[') {
                        datum_depth += 1;
                    } else if (src[i] == ')' or src[i] == ']') {
                        datum_depth -= 1;
                    }
                    i += 1;
                }
                if (datum_depth > 0) depth += 1;
                i -= 1;
            } else if (src[i] == '"') {
                i += 1;
                while (i < src.len) {
                    if (src[i] == '\\' and i + 1 < src.len) {
                        i += 2;
                        continue;
                    }
                    if (src[i] == '"') break;
                    i += 1;
                }
            } else {
                while (i < src.len and src[i] != ' ' and src[i] != '\t' and src[i] != '\n' and
                    src[i] != ')' and src[i] != '(' and src[i] != ';') : (i += 1)
                {}
                i -= 1;
            }
            continue;
        }
        // Character literals: #\x or #\space etc.
        if (ch == '#' and i + 1 < src.len and src[i + 1] == '\\') {
            i += 2; // skip #\ — now i points at the character after backslash
            if (i >= src.len) continue;
            // The character itself (could be anything: paren, letter, etc.)
            const first = src[i];
            // Check for multi-char names: if it's a letter, consume until delimiter
            if ((first >= 'a' and first <= 'z') or (first >= 'A' and first <= 'Z')) {
                i += 1;
                while (i < src.len and ((src[i] >= 'a' and src[i] <= 'z') or (src[i] >= 'A' and src[i] <= 'Z'))) : (i += 1) {}
                i -= 1; // back up for outer loop's i+=1
            }
            // For single-char names like #\( or #\), i stays on that char
            // and the outer loop's i+=1 skips past it
            continue;
        }
        // Pipe-quoted symbols: |...|
        if (ch == '|') {
            i += 1;
            while (i < src.len and src[i] != '|') {
                if (src[i] == '\\' and i + 1 < src.len) i += 1;
                i += 1;
            }
            continue;
        }
        switch (ch) {
            '"' => in_string = true,
            ';' => in_line_comment = true,
            '(' => depth += 1,
            ')' => depth -= 1,
            else => {},
        }
    }
    if (in_string) depth += 1;
    if (block_comment_depth > 0) depth += 1;
    return depth;
}

pub fn repl(vm: *vm_mod.VM) !void {
    const allocator = vm.gc.allocator;

    writeStdout("Kaappi Scheme v" ++ version ++ "\n");
    writeStdout("Type ,help for commands, ,quit to exit.\n\n");

    repl_vm = vm;
    ln.setMultiLine(true);
    ln.historySetMaxLen(1000);

    var hist_path_buf: [512]u8 = undefined;
    const hist_path: ?[*:0]const u8 = blk: {
        const home_ptr: ?[*:0]const u8 = std.c.getenv("HOME");
        const home = if (home_ptr) |p| std.mem.span(p) else break :blk null;
        const dir = std.fmt.bufPrintZ(hist_path_buf[0..500], "{s}/.kaappi", .{home}) catch break :blk null;
        _ = std.c.mkdir(dir.ptr, 0o755);
        const path = std.fmt.bufPrintZ(&hist_path_buf, "{s}/.kaappi/history", .{home}) catch break :blk null;
        break :blk path;
    };
    if (hist_path) |p| ln.historyLoad(p);

    ln.setCompletionCallback(&completionCallback);
    ln.setHighlightCallback(&highlightCallback);

    var input_buf: std.ArrayList(u8) = .empty;
    defer input_buf.deinit(allocator);

    while (true) {
        const prompt: [*:0]const u8 = if (input_buf.items.len > 0) "  ... " else "kaappi> ";
        const line_ptr = ln.linenoise(prompt) orelse {
            const err = std.c._errno().*;
            if (err == @intFromEnum(std.posix.E.AGAIN)) {
                if (input_buf.items.len > 0) {
                    input_buf.clearRetainingCapacity();
                }
                writeStdout("\n");
                continue;
            }
            if (input_buf.items.len > 0) {
                input_buf.clearRetainingCapacity();
                writeStdout("\n");
                continue;
            }
            break;
        };
        defer ln.free(@ptrCast(line_ptr));

        const line = std.mem.span(line_ptr);
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (input_buf.items.len == 0 and trimmed.len == 0) continue;
        if (input_buf.items.len == 0 and std.mem.eql(u8, trimmed, "(exit)")) break;

        // If pasted text contains newlines, echo it clearly
        const has_newlines = std.mem.indexOf(u8, line, "\n") != null;
        if (has_newlines and input_buf.items.len == 0) {
            writeStdout(line);
            writeStdout("\n");
        }

        if (input_buf.items.len > 0) {
            input_buf.append(allocator, '\n') catch continue;
        }
        input_buf.appendSlice(allocator, line) catch continue;

        if (parenDepth(input_buf.items) > 0) continue;

        const full_input = input_buf.items;
        const debug_trimmed = std.mem.trim(u8, full_input, " \t\r\n");

        // Debug commands (comma-prefixed)
        if (std.mem.startsWith(u8, debug_trimmed, ",break ")) {
            const bp_name_src = std.mem.trim(u8, debug_trimmed[7..], " ");
            if (vm.breakpoint_count >= 16) {
                writeStdout("Too many breakpoints (max 16)\n");
                input_buf.clearRetainingCapacity();
                continue;
            }
            const bp_name = allocator.dupe(u8, bp_name_src) catch continue;
            vm.breakpoints[vm.breakpoint_count] = .{ .name = bp_name };
            vm.breakpoint_count += 1;
            vm.debug_mode = true;
            vm.step_mode = .continue_to_break;
            writeStdout("Breakpoint set on ");
            writeStdout(bp_name);
            writeStdout("\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",condition ")) {
            const rest = std.mem.trim(u8, debug_trimmed[11..], " ");
            if (std.mem.indexOfScalar(u8, rest, ' ')) |space| {
                const id_str = rest[0..space];
                const expr = std.mem.trim(u8, rest[space + 1 ..], " ");
                const id = std.fmt.parseInt(usize, id_str, 10) catch {
                    writeStdout("Usage: ,condition <id> <expr>\n");
                    input_buf.clearRetainingCapacity();
                    continue;
                };
                if (id < vm.breakpoint_count) {
                    const owned_expr = allocator.dupe(u8, expr) catch continue;
                    if (vm.breakpoints[id].condition) |old_cond| allocator.free(old_cond);
                    vm.breakpoints[id].condition = owned_expr;
                    writeStdout("Condition set\n");
                } else {
                    writeStdout("Invalid breakpoint ID\n");
                }
            } else {
                writeStdout("Usage: ,condition <id> <expr>\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",breakpoints")) {
            for (vm.breakpoints[0..vm.breakpoint_count], 0..) |bp, idx| {
                var dbuf: [64]u8 = undefined;
                const s = std.fmt.bufPrint(&dbuf, "  [{d}] {s}", .{ idx, bp.name }) catch "";
                writeStdout(s);
                if (bp.condition) |cond| {
                    writeStdout(" if ");
                    writeStdout(cond);
                }
                writeStdout("\n");
            }
            if (vm.breakpoint_count == 0) {
                writeStdout("  (no breakpoints)\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",delete all")) {
            for (vm.breakpoints[0..vm.breakpoint_count]) |bp| {
                allocator.free(bp.name);
                if (bp.condition) |cond| allocator.free(cond);
            }
            vm.breakpoint_count = 0;
            vm.debug_mode = false;
            vm.step_mode = .none;
            writeStdout("All breakpoints deleted\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",step ")) {
            const step_expr = debug_trimmed[6..];
            vm.debug_mode = true;
            vm.step_mode = .step;
            evalInput(vm, allocator, step_expr);
            vm.debug_mode = false;
            vm.step_mode = .none;
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",time ")) {
            const time_expr = debug_trimmed[6..];
            var ts: std.c.timespec = undefined;
            _ = std.c.clock_gettime(.MONOTONIC, &ts);
            evalInput(vm, allocator, time_expr);
            var te: std.c.timespec = undefined;
            _ = std.c.clock_gettime(.MONOTONIC, &te);
            const secs = @as(f64, @floatFromInt(te.sec - ts.sec)) +
                @as(f64, @floatFromInt(te.nsec - ts.nsec)) / 1_000_000_000.0;
            var tbuf: [64]u8 = undefined;
            const ts_str = std.fmt.bufPrint(&tbuf, "; {d:.3} seconds\n", .{secs}) catch "; ? seconds\n";
            writeStdout(ts_str);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",profile ")) {
            const profile_expr = debug_trimmed[9..];
            reporting.resetProfileCounters(vm.gc);
            vm.profile_mode = true;
            evalInput(vm, allocator, profile_expr);
            vm.profile_mode = false;
            reporting.printProfileReport(vm.gc);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",gc")) {
            reporting.printGcStats(vm.gc);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",quit") or std.mem.eql(u8, debug_trimmed, ",exit")) {
            break;
        }
        if (std.mem.eql(u8, debug_trimmed, ",version")) {
            writeStdout("Kaappi Scheme v" ++ version ++ "\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",load ")) {
            const load_path = std.mem.trim(u8, debug_trimmed[6..], " ");
            if (load_path.len == 0) {
                writeStderr(",load requires a file path\n");
            } else {
                var load_buf: [1024]u8 = undefined;
                const load_expr = std.fmt.bufPrint(&load_buf, "(load \"{s}\")", .{load_path}) catch {
                    writeStderr("path too long\n");
                    input_buf.clearRetainingCapacity();
                    continue;
                };
                evalInput(vm, allocator, load_expr);
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",import ")) {
            const import_expr = debug_trimmed[8..];
            var ir = reader.Reader.init(vm.gc, import_expr);
            defer ir.deinit();
            var import_list = types.NIL;
            var import_root = import_list;
            vm.gc.pushRoot(&import_root) catch {
                writeStderr("out of memory\n");
                input_buf.clearRetainingCapacity();
                continue;
            };
            var read_ok = true;
            while (ir.hasMore() catch false) {
                var datum = ir.readDatum() catch {
                    writeStderr("read error in import spec\n");
                    read_ok = false;
                    break;
                };
                vm.gc.pushRoot(&datum) catch {
                    writeStderr("out of memory\n");
                    read_ok = false;
                    break;
                };
                var pair = vm.gc.allocPair(datum, types.NIL) catch {
                    vm.gc.popRoot();
                    writeStderr("out of memory\n");
                    read_ok = false;
                    break;
                };
                vm.gc.popRoot();
                if (import_root == types.NIL) {
                    import_root = pair;
                    import_list = pair;
                } else {
                    types.toObject(import_list).as(types.Pair).cdr = pair;
                    import_list = pair;
                }
                _ = &pair;
            }
            if (read_ok and import_root != types.NIL) {
                _ = vm_library.handleImport(vm, import_root) catch {
                    const detail = vm.getErrorDetail();
                    if (detail.len > 0) {
                        writeStderr("import error: ");
                        writeStderr(detail);
                        writeStderr("\n");
                    } else {
                        writeStderr("import error\n");
                    }
                };
            }
            vm.gc.popRoot();
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",dis ")) {
            const dis_expr = debug_trimmed[5..];
            var dis_buf: [1024]u8 = undefined;
            const dis_call = std.fmt.bufPrint(&dis_buf, "(disassemble {s})", .{dis_expr}) catch {
                writeStderr("expression too long\n");
                input_buf.clearRetainingCapacity();
                continue;
            };
            evalInput(vm, allocator, dis_call);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",help")) {
            writeStdout(
                \\Commands:
                \\  ,help             Show this message
                \\  ,quit             Exit the REPL
                \\
                \\ -- Evaluation:
                \\  ,time <expr>      Measure execution time
                \\  ,type <expr>      Show result type
                \\  ,expand <expr>    Show macro expansion
                \\  ,profile <expr>   Profile timing, calls, and allocations
                \\  ,dis <expr>       Disassemble a procedure
                \\
                \\ -- Inspection:
                \\  ,describe <sym>   Show procedure arity and type
                \\  ,apropos <str>    Search bindings by substring
                \\  ,env [prefix]     List bindings (optionally filtered by prefix)
                \\
                \\ -- Debugging:
                \\  ,break <name>     Set breakpoint on function
                \\  ,breakpoints      List active breakpoints
                \\  ,delete all       Clear all breakpoints
                \\  ,step <expr>      Evaluate with single-stepping
                \\  ,condition <id> <expr>  Set breakpoint condition
                \\
                \\ -- System:
                \\  ,gc               Show GC statistics
                \\  ,version          Show Kaappi version
                \\  ,load <file>      Load and run a Scheme file
                \\  ,import <lib>     Import a library (e.g. ,import (srfi 1))
                \\
                \\The variable _ holds the last result.
                \\
            );
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",type ")) {
            const type_expr = debug_trimmed[6..];
            evalInputTyped(vm, allocator, type_expr, .show_type);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",describe ")) {
            const sym_name = std.mem.trim(u8, debug_trimmed[10..], " ");
            describeSymbol(vm, allocator, sym_name);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",apropos ")) {
            const needle = std.mem.trim(u8, debug_trimmed[9..], " ");
            var env_count: usize = 0;
            var git3 = vm.globals.keyIterator();
            while (git3.next()) |key| {
                if (needle.len == 0 or containsSubstring(key.*, needle)) {
                    writeStdout("  ");
                    writeStdout(key.*);
                    writeStdout("\n");
                    env_count += 1;
                }
            }
            var cbuf2: [64]u8 = undefined;
            const cs2 = std.fmt.bufPrint(&cbuf2, "; {d} matches\n", .{env_count}) catch "\n";
            writeStdout(cs2);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",expand ")) {
            const expand_src = debug_trimmed[8..];
            var er = reader.Reader.init(vm.gc, expand_src);
            defer er.deinit();
            const expr = er.readDatum() catch {
                writeStderr("read error\n");
                input_buf.clearRetainingCapacity();
                continue;
            };
            if (types.isPair(expr) and types.isSymbol(types.car(expr))) {
                const ename = types.symbolName(types.car(expr));
                if (vm.macros.get(ename)) |transformer| {
                    const expanded = expander.expandMacro(vm.gc, expr, transformer, &vm.globals, &vm.macros) catch {
                        writeStderr("expansion error\n");
                        input_buf.clearRetainingCapacity();
                        continue;
                    };
                    const s = printer.valueToString(allocator, expanded, .write) catch "";
                    defer if (s.len > 0) allocator.free(s);
                    writeStdout(s);
                    writeStdout("\n");
                } else {
                    writeStderr("not a macro: ");
                    writeStderr(ename);
                    writeStderr("\n");
                }
            } else {
                writeStderr("not a macro invocation\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",env") or std.mem.startsWith(u8, debug_trimmed, ",env ")) {
            const prefix = if (debug_trimmed.len > 5) std.mem.trim(u8, debug_trimmed[5..], " ") else "";
            var env_count: usize = 0;
            var git2 = vm.globals.keyIterator();
            while (git2.next()) |key| {
                if (prefix.len == 0 or std.mem.startsWith(u8, key.*, prefix)) {
                    writeStdout("  ");
                    writeStdout(key.*);
                    writeStdout("\n");
                    env_count += 1;
                }
            }
            var cbuf: [64]u8 = undefined;
            const cs = std.fmt.bufPrint(&cbuf, "; {d} bindings\n", .{env_count}) catch "\n";
            writeStdout(cs);
            input_buf.clearRetainingCapacity();
            continue;
        }

        // Catch-all for unrecognized or incomplete comma commands
        if (debug_trimmed.len > 0 and debug_trimmed[0] == ',') {
            const usage = getCommandUsage(debug_trimmed);
            if (usage) |msg| {
                writeStderr(msg);
            } else {
                writeStderr("unknown command: ");
                const end = std.mem.indexOfScalar(u8, debug_trimmed, ' ') orelse debug_trimmed.len;
                writeStderr(debug_trimmed[0..end]);
                writeStderr("\nType ,help for available commands.\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }

        // Add to history with newlines replaced by spaces for clean display
        var hist_buf: std.ArrayList(u8) = .empty;
        defer hist_buf.deinit(allocator);
        hist_buf.appendSlice(allocator, full_input) catch {};
        for (hist_buf.items) |*ch| {
            if (ch.* == '\n') ch.* = ' ';
        }
        hist_buf.append(allocator, 0) catch {};
        ln.historyAdd(@ptrCast(hist_buf.items.ptr));

        evalInputTyped(vm, allocator, full_input, .store_last);

        input_buf.clearRetainingCapacity();
    }

    if (hist_path) |p| ln.historySave(p);
    repl_vm = null;
}

fn getCommandUsage(input: []const u8) ?[]const u8 {
    const cmd = blk: {
        const end = std.mem.indexOfScalar(u8, input, ' ') orelse input.len;
        break :blk input[0..end];
    };
    const commands = [_]struct { name: []const u8, usage: []const u8 }{
        .{ .name = ",time", .usage = "usage: ,time <expr>\n" },
        .{ .name = ",type", .usage = "usage: ,type <expr>\n" },
        .{ .name = ",describe", .usage = "usage: ,describe <symbol>\n" },
        .{ .name = ",apropos", .usage = "usage: ,apropos <string>\n" },
        .{ .name = ",expand", .usage = "usage: ,expand <expr>\n" },
        .{ .name = ",profile", .usage = "usage: ,profile <expr>\n" },
        .{ .name = ",step", .usage = "usage: ,step <expr>\n" },
        .{ .name = ",break", .usage = "usage: ,break <name>\n" },
        .{ .name = ",load", .usage = "usage: ,load <file>\n" },
        .{ .name = ",import", .usage = "usage: ,import <lib>  (e.g. ,import (srfi 1))\n" },
        .{ .name = ",dis", .usage = "usage: ,dis <expr>\n" },
        .{ .name = ",delete", .usage = "usage: ,delete all\n" },
        .{ .name = ",condition", .usage = "usage: ,condition <id> <expr>\n" },
    };
    for (&commands) |entry| {
        if (std.mem.eql(u8, cmd, entry.name)) return entry.usage;
    }
    return null;
}

fn containsSubstring(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) return true;
    }
    return false;
}

fn getTypeName(val: types.Value) []const u8 {
    if (types.isFixnum(val)) return "integer";
    if (val == types.NIL) return "nil";
    if (val == types.TRUE or val == types.FALSE) return "boolean";
    if (val == types.VOID) return "void";
    if (val == types.EOF) return "eof-object";
    if (types.isChar(val)) return "char";
    if (!types.isPointer(val)) return "unknown";
    const obj = types.toObject(val);
    return switch (obj.tag) {
        .pair => "pair",
        .symbol => "symbol",
        .string => "string",
        .closure => "procedure",
        .native_fn => "procedure",
        .function => "function",
        .vector => "vector",
        .bytevector => "bytevector",
        .port => "port",
        .flonum => "number",
        .complex => "complex",
        .transformer => "syntax",
        .error_object => "error",
        .record_type => "record-type",
        .record_instance => "record",
        .continuation => "continuation",
        .multiple_values => "values",
        .promise => "promise",
        .parameter => "parameter",
        .rational => "rational",
        .bignum => "integer",
        .hash_table => "hash-table",
        else => "object",
    };
}

fn describeSymbol(vm: *vm_mod.VM, allocator: std.mem.Allocator, name: []const u8) void {
    const val_opt = vm.globals.get(name);
    if (val_opt == null) {
        writeStdout("  not found: ");
        writeStdout(name);
        writeStdout("\n");
        return;
    }
    const val = val_opt.?;
    writeStdout("  ");
    writeStdout(name);
    writeStdout("\n    type: ");
    writeStdout(getTypeName(val));
    writeStdout("\n");

    if (types.isPointer(val)) {
        const obj = types.toObject(val);
        if (obj.tag == .native_fn) {
            const nfn = obj.as(types.NativeFn);
            var abuf: [64]u8 = undefined;
            switch (nfn.arity) {
                .exact => |n| {
                    const s = std.fmt.bufPrint(&abuf, "    arity: {d}\n", .{n}) catch "";
                    writeStdout(s);
                },
                .variadic => |min| {
                    const s = std.fmt.bufPrint(&abuf, "    arity: {d}+\n", .{min}) catch "";
                    writeStdout(s);
                },
            }
        } else if (obj.tag == .closure) {
            const cls = obj.as(types.Closure);
            const func = cls.func;
            var abuf: [128]u8 = undefined;
            const s = std.fmt.bufPrint(&abuf, "    arity: {d}, locals: {d}\n", .{ func.arity, func.locals_count }) catch "";
            writeStdout(s);
            if (func.source_name) |src| {
                writeStdout("    source: ");
                writeStdout(src);
                var lbuf: [32]u8 = undefined;
                const ls = std.fmt.bufPrint(&lbuf, ":{d}\n", .{func.source_line}) catch "\n";
                writeStdout(ls);
            }
        } else if (obj.tag == .transformer) {
            writeStdout("    (syntax transformer)\n");
        }
    }
    _ = allocator;
}

const EvalMode = enum { normal, store_last, show_type };

fn evalInputTyped(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8, mode: EvalMode) void {
    evalInputInner(vm, allocator, input, mode);
}

fn evalInput(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8) void {
    evalInputInner(vm, allocator, input, .normal);
}

fn evalInputInner(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8, mode: EvalMode) void {
    var r = reader.Reader.initWithName(vm.gc, input, "<repl>");
    defer r.deinit();

    while (r.hasMore() catch |err| blk: {
        const lc = r.getLineCol();
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "<repl>:{d}:{d}: read error: {}\n", .{ lc.line, lc.col, err }) catch "read error\n";
        writeStderr(s);
        break :blk false;
    }) {
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "<repl>:{d}:{d}: read error: {}\n", .{ lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            break;
        };

        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                const detail = vm.getErrorDetail();
                if (detail.len > 0) {
                    writeStderr("error: ");
                    writeStderr(detail);
                    writeStderr("\n");
                } else {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "runtime error: {}\n", .{err}) catch "runtime error\n";
                    writeStderr(s);
                }
                vm.last_error_detail_len = 0;
                break;
            };
            var dr = result;
            if (types.isMultipleValues(dr)) {
                const mv = types.toObject(dr).as(types.MultipleValues);
                dr = if (mv.values.len > 0) mv.values[0] else types.VOID;
            }
            if (dr != types.VOID) {
                if (mode == .show_type) {
                    writeStdout("; ");
                    writeStdout(getTypeName(dr));
                    writeStdout("\n");
                } else {
                    const s = printer.valueToString(allocator, dr, .write) catch continue;
                    defer allocator.free(s);
                    writeStdout(s);
                    writeStdout("\n");
                }
                if (mode == .store_last) {
                    vm.globals.put("_", dr) catch {};
                }
            }
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, &vm.globals, 0, "<repl>") catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "<repl>:{d}: compile error: {}\n", .{ lc.line, err }) catch "compile error\n";
            writeStderr(s);
            break;
        };

        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val) catch {
            writeStderr("error: out of memory while rooting function\n");
            break;
        };

        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            const detail = vm.getErrorDetail();
            if (detail.len > 0) {
                writeStderr("error: ");
                writeStderr(detail);
                writeStderr("\n");
            } else {
                var errbuf: [256]u8 = undefined;
                const s = std.fmt.bufPrint(&errbuf, "runtime error: {}\n", .{err}) catch "runtime error\n";
                writeStderr(s);
            }
            const trace = vm.getLastStackTrace();
            if (trace.len > 1) {
                for (trace[1..]) |sf| {
                    var tbuf: [256]u8 = undefined;
                    if (sf.name) |name| {
                        const ts = std.fmt.bufPrint(&tbuf, "  in {s} ({s}:{d})\n", .{ name, sf.source orelse "?", sf.line }) catch continue;
                        writeStderr(ts);
                    } else if (sf.line > 0) {
                        const ts = std.fmt.bufPrint(&tbuf, "  called from {s}:{d}\n", .{ sf.source orelse "?", sf.line }) catch continue;
                        writeStderr(ts);
                    }
                }
            }
            vm.last_error_detail_len = 0;
            break;
        };
        vm.gc.popRoot();

        if (result != types.VOID) {
            if (mode == .show_type) {
                writeStdout("; ");
                writeStdout(getTypeName(result));
                writeStdout("\n");
            } else {
                const s = printer.prettyPrint(allocator, result, 80) catch
                    (printer.valueToString(allocator, result, .write) catch continue);
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            if (mode == .store_last) {
                vm.globals.put("_", result) catch {};
            }
        }
    }
}
