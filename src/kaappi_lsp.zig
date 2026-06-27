const std = @import("std");
const builtin = @import("builtin");
pub const types = @import("types.zig");
pub const memory = @import("memory.zig");
pub const reader = @import("reader.zig");
pub const compiler = @import("compiler.zig");
pub const compiler_forms = @import("compiler_forms.zig");
pub const vm_mod = @import("vm.zig");
pub const primitives = @import("primitives.zig");
pub const primitives_arithmetic = @import("primitives_arithmetic.zig");
pub const primitives_io = @import("primitives_io.zig");
pub const primitives_control = @import("primitives_control.zig");
pub const primitives_vector = @import("primitives_vector.zig");
pub const primitives_string = @import("primitives_string.zig");
pub const primitives_char = @import("primitives_char.zig");
pub const primitives_cxr = @import("primitives_cxr.zig");
pub const primitives_bytevector = @import("primitives_bytevector.zig");
pub const primitives_lazy = @import("primitives_lazy.zig");
pub const primitives_r7rs = @import("primitives_r7rs.zig");
pub const printer = @import("printer.zig");
pub const expander = @import("expander.zig");
pub const library = @import("library.zig");
pub const ffi = @import("ffi.zig");
pub const primitives_ffi = @import("primitives_ffi.zig");
pub const primitives_srfi1 = @import("primitives_srfi1.zig");
pub const primitives_hashtable = @import("primitives_hashtable.zig");
pub const primitives_random = @import("primitives_random.zig");
pub const bytecode_file = @import("bytecode_file.zig");
pub const ffi_callback = @import("ffi_callback.zig");
pub const embedded_bytecode = @import("embedded_bytecode");
pub const fiber_mod = @import("fiber.zig");
pub const primitives_fiber = @import("primitives_fiber.zig");

const version = "0.1.0";

fn log(msg: []const u8) void {
    _ = std.posix.system.write(2, msg.ptr, msg.len);
}

fn logFmt(buf: []u8, comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(buf, fmt, args) catch return;
    log(s);
}

// ---- JSON helpers (minimal) ----

fn jsonString(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, s: []const u8) void {
    buf.append(allocator, '"') catch return;
    for (s) |ch| {
        switch (ch) {
            '\\' => buf.appendSlice(allocator, "\\\\") catch return,
            '"' => buf.appendSlice(allocator, "\\\"") catch return,
            '\n' => buf.appendSlice(allocator, "\\n") catch return,
            '\r' => buf.appendSlice(allocator, "\\r") catch return,
            '\t' => buf.appendSlice(allocator, "\\t") catch return,
            else => buf.append(allocator, ch) catch return,
        }
    }
    buf.append(allocator, '"') catch return;
}

fn jsonInt(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, n: i64) void {
    var tmp: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "{d}", .{n}) catch return;
    buf.appendSlice(allocator, s) catch return;
}

// Simple JSON value extractor — finds "key": "value" or "key": number
fn jsonGetString(json: []const u8, key: []const u8) ?[]const u8 {
    var search_buf: [256]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;
    const pos = std.mem.indexOf(u8, json, search) orelse return null;
    var i = pos + search.len;
    // skip whitespace and colon
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len or json[i] != '"') return null;
    i += 1; // skip opening quote
    const start = i;
    while (i < json.len and json[i] != '"') : (i += 1) {
        if (json[i] == '\\') i += 1; // skip escaped char
    }
    return json[start..i];
}

fn jsonGetInt(json: []const u8, key: []const u8) ?i64 {
    var search_buf: [256]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;
    const pos = std.mem.indexOf(u8, json, search) orelse return null;
    var i = pos + search.len;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len) return null;
    const start = i;
    if (json[i] == '-') i += 1;
    while (i < json.len and json[i] >= '0' and json[i] <= '9') : (i += 1) {}
    return std.fmt.parseInt(i64, json[start..i], 10) catch null;
}

fn jsonGetObject(json: []const u8, key: []const u8) ?[]const u8 {
    var search_buf: [256]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;
    const pos = std.mem.indexOf(u8, json, search) orelse return null;
    var i = pos + search.len;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len or json[i] != '{') return null;
    var depth: usize = 0;
    const start = i;
    while (i < json.len) : (i += 1) {
        if (json[i] == '{') depth += 1 else if (json[i] == '}') {
            depth -= 1;
            if (depth == 0) return json[start .. i + 1];
        }
    }
    return null;
}

// ---- LSP message I/O ----

fn readMessage(allocator: std.mem.Allocator) ?[]u8 {
    var header_buf: [256]u8 = undefined;
    var header_len: usize = 0;
    var content_length: usize = 0;

    // Read headers until blank line
    while (true) {
        var byte: [1]u8 = undefined;
        const n = std.posix.read(0, &byte) catch return null;
        if (n == 0) return null;
        if (header_len < header_buf.len) {
            header_buf[header_len] = byte[0];
            header_len += 1;
        }
        if (header_len >= 4 and
            std.mem.eql(u8, header_buf[header_len - 4 .. header_len], "\r\n\r\n"))
        {
            // Parse Content-Length
            const headers = header_buf[0..header_len];
            if (std.mem.indexOf(u8, headers, "Content-Length: ")) |cl_pos| {
                const cl_start = cl_pos + 16;
                var cl_end = cl_start;
                while (cl_end < headers.len and headers[cl_end] >= '0' and headers[cl_end] <= '9') : (cl_end += 1) {}
                content_length = std.fmt.parseInt(usize, headers[cl_start..cl_end], 10) catch return null;
            }
            break;
        }
    }

    if (content_length == 0) return null;

    // Read body
    const body = allocator.alloc(u8, content_length) catch return null;
    var total: usize = 0;
    while (total < content_length) {
        const n = std.posix.read(0, body[total..]) catch {
            allocator.free(body);
            return null;
        };
        if (n == 0) {
            allocator.free(body);
            return null;
        }
        total += n;
    }
    return body;
}

fn writeMessage(allocator: std.mem.Allocator, json: []const u8) void {
    var header: [64]u8 = undefined;
    const h = std.fmt.bufPrint(&header, "Content-Length: {d}\r\n\r\n", .{json.len}) catch return;
    _ = std.posix.system.write(1, h.ptr, h.len);
    _ = std.posix.system.write(1, json.ptr, json.len);
    _ = allocator;
}

fn sendResponse(allocator: std.mem.Allocator, id: i64, result: []const u8) void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":") catch return;
    jsonInt(&buf, allocator, id);
    buf.appendSlice(allocator, ",\"result\":") catch return;
    buf.appendSlice(allocator, result) catch return;
    buf.append(allocator, '}') catch return;
    writeMessage(allocator, buf.items);
}

fn sendNotification(allocator: std.mem.Allocator, method: []const u8, params: []const u8) void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"method\":") catch return;
    jsonString(&buf, allocator, method);
    buf.appendSlice(allocator, ",\"params\":") catch return;
    buf.appendSlice(allocator, params) catch return;
    buf.append(allocator, '}') catch return;
    writeMessage(allocator, buf.items);
}

// ---- Document store ----

var documents: std.StringHashMap([]const u8) = undefined;
var doc_allocator: std.mem.Allocator = undefined;

fn storeDocument(uri: []const u8, text: []const u8) void {
    const uri_copy = doc_allocator.dupe(u8, uri) catch return;
    const text_copy = doc_allocator.dupe(u8, text) catch {
        doc_allocator.free(uri_copy);
        return;
    };
    if (documents.fetchRemove(uri)) |old| {
        doc_allocator.free(old.value);
        doc_allocator.free(old.key);
    }
    documents.put(uri_copy, text_copy) catch return;
}

fn removeDocument(uri: []const u8) void {
    if (documents.fetchRemove(uri)) |old| {
        doc_allocator.free(old.value);
        doc_allocator.free(old.key);
    }
}

fn getDocument(uri: []const u8) ?[]const u8 {
    return documents.get(uri);
}

// ---- Type name helper (same as main.zig) ----

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
        .transformer => "syntax",
        .error_object => "error",
        .continuation => "continuation",
        .hash_table => "hash-table",
        else => "object",
    };
}

fn getArity(val: types.Value) ?[]const u8 {
    if (!types.isPointer(val)) return null;
    const obj = types.toObject(val);
    if (obj.tag == .native_fn) {
        const nfn = obj.as(types.NativeFn);
        var buf: [32]u8 = undefined;
        return switch (nfn.arity) {
            .exact => |n| std.fmt.bufPrint(&buf, "{d}", .{n}) catch null,
            .variadic => |n| std.fmt.bufPrint(&buf, "{d}+", .{n}) catch null,
        };
    }
    if (obj.tag == .closure) {
        const cls = obj.as(types.Closure);
        var buf: [32]u8 = undefined;
        return std.fmt.bufPrint(&buf, "{d}", .{cls.func.arity}) catch null;
    }
    return null;
}

// ---- LSP handlers ----

fn handleInitialize(allocator: std.mem.Allocator, id: i64) void {
    sendResponse(allocator, id,
        \\{"capabilities":{"textDocumentSync":1,"completionProvider":{"resolveProvider":false,"triggerCharacters":[]},"hoverProvider":true,"documentSymbolProvider":true},"serverInfo":{"name":"kaappi-lsp","version":"0.1.0"}}
    );
}

fn handleCompletion(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: i64, params: []const u8) void {
    // Get document and position
    const td = jsonGetObject(params, "textDocument") orelse "";
    const uri = jsonGetString(td, "uri") orelse "";
    const pos_obj = jsonGetObject(params, "position") orelse "";
    const line = jsonGetInt(pos_obj, "line") orelse 0;
    const character = jsonGetInt(pos_obj, "character") orelse 0;

    const text = getDocument(uri) orelse "";
    const prefix = getSymbolAtPosition(text, @intCast(line), @intCast(character));

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    buf.append(allocator, '[') catch return;
    var first = true;
    var git = vm.globals.keyIterator();
    while (git.next()) |key| {
        if (prefix.len == 0 or std.mem.startsWith(u8, key.*, prefix)) {
            if (!first) buf.append(allocator, ',') catch {};
            first = false;
            buf.appendSlice(allocator, "{\"label\":") catch {};
            jsonString(&buf, allocator, key.*);

            // Determine kind
            if (vm.globals.get(key.*)) |val| {
                const tn = getTypeName(val);
                if (std.mem.eql(u8, tn, "procedure")) {
                    buf.appendSlice(allocator, ",\"kind\":3") catch {};
                } else if (std.mem.eql(u8, tn, "syntax")) {
                    buf.appendSlice(allocator, ",\"kind\":14") catch {};
                } else {
                    buf.appendSlice(allocator, ",\"kind\":6") catch {};
                }
            }
            buf.append(allocator, '}') catch {};
        }
    }
    buf.append(allocator, ']') catch return;
    sendResponse(allocator, id, buf.items);
}

fn handleHover(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: i64, params: []const u8) void {
    const td = jsonGetObject(params, "textDocument") orelse "";
    const uri = jsonGetString(td, "uri") orelse "";
    const pos_obj = jsonGetObject(params, "position") orelse "";
    const line = jsonGetInt(pos_obj, "line") orelse 0;
    const character = jsonGetInt(pos_obj, "character") orelse 0;

    const text = getDocument(uri) orelse "";
    const symbol = getFullSymbolAtPosition(text, @intCast(line), @intCast(character));

    if (symbol.len == 0) {
        sendResponse(allocator, id, "null");
        return;
    }

    const val_opt = vm.globals.get(symbol);
    if (val_opt == null) {
        sendResponse(allocator, id, "null");
        return;
    }
    const val = val_opt.?;
    const type_name = getTypeName(val);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    buf.appendSlice(allocator, "{\"contents\":{\"kind\":\"markdown\",\"value\":") catch return;

    var md: std.ArrayList(u8) = .empty;
    defer md.deinit(allocator);
    md.appendSlice(allocator, "**") catch {};
    md.appendSlice(allocator, type_name) catch {};
    md.appendSlice(allocator, "** `") catch {};
    md.appendSlice(allocator, symbol) catch {};
    md.appendSlice(allocator, "`") catch {};

    if (getArity(val)) |arity| {
        md.appendSlice(allocator, "\\n\\nArity: ") catch {};
        md.appendSlice(allocator, arity) catch {};
    }

    jsonString(&buf, allocator, md.items);
    buf.appendSlice(allocator, "}}") catch {};
    sendResponse(allocator, id, buf.items);
}

fn handleDocumentSymbol(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: i64, params: []const u8) void {
    const td = jsonGetObject(params, "textDocument") orelse "";
    const uri = jsonGetString(td, "uri") orelse "";
    const text = getDocument(uri) orelse "";

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    result.append(allocator, '[') catch return;
    var first = true;

    var r = reader.Reader.init(vm.gc, text);
    defer r.deinit();

    while (r.hasMore()) {
        const lc = r.getLineCol();
        const expr = r.readDatum() catch break;

        if (!types.isPair(expr)) continue;
        const head = types.car(expr);
        if (!types.isSymbol(head)) continue;
        const form = types.symbolName(head);

        var name: ?[]const u8 = null;
        var kind: u8 = 12; // Function

        if (std.mem.eql(u8, form, "define")) {
            const rest = types.cdr(expr);
            if (rest == types.NIL) continue;
            const target = types.car(rest);
            if (types.isSymbol(target)) {
                name = types.symbolName(target);
                kind = 13; // Variable
            } else if (types.isPair(target)) {
                const fn_name = types.car(target);
                if (types.isSymbol(fn_name)) {
                    name = types.symbolName(fn_name);
                    kind = 12; // Function
                }
            }
        } else if (std.mem.eql(u8, form, "define-syntax")) {
            const rest = types.cdr(expr);
            if (rest != types.NIL and types.isPair(rest)) {
                const syn_name = types.car(rest);
                if (types.isSymbol(syn_name)) {
                    name = types.symbolName(syn_name);
                    kind = 14; // Constructor (macro)
                }
            }
        } else if (std.mem.eql(u8, form, "define-record-type")) {
            const rest = types.cdr(expr);
            if (rest != types.NIL and types.isPair(rest)) {
                const rec_name = types.car(rest);
                if (types.isSymbol(rec_name)) {
                    name = types.symbolName(rec_name);
                    kind = 23; // Struct
                }
            }
        } else if (std.mem.eql(u8, form, "define-library")) {
            kind = 4; // Package
            name = "(library)";
        }

        if (name) |n| {
            if (!first) result.append(allocator, ',') catch {};
            first = false;
            const line: i64 = @intCast(lc.line -| 1);
            const s = std.fmt.allocPrint(allocator,
                \\{{"name":"{s}","kind":{d},"location":{{"uri":"{s}","range":{{"start":{{"line":{d},"character":0}},"end":{{"line":{d},"character":0}}}}}}}}
            , .{ n, kind, uri, line, line }) catch continue;
            defer allocator.free(s);
            result.appendSlice(allocator, s) catch {};
        }
    }

    result.append(allocator, ']') catch return;
    sendResponse(allocator, id, result.items);
}

fn handleDidOpenOrChange(allocator: std.mem.Allocator, vm: *vm_mod.VM, params: []const u8) void {
    const td = jsonGetObject(params, "textDocument") orelse "";
    const uri = jsonGetString(td, "uri") orelse return;

    // For didOpen, text is in textDocument.text
    // For didChange with full sync, text is in contentChanges[0].text
    var text = jsonGetString(td, "text");
    if (text == null) {
        // Try contentChanges
        if (std.mem.indexOf(u8, params, "\"text\"")) |_| {
            // Find the last "text" field (usually in contentChanges)
            text = jsonGetString(params, "text");
        }
    }

    if (text) |t| {
        storeDocument(uri, t);
        runDiagnostics(allocator, vm, uri, t);
    }
}

fn runDiagnostics(allocator: std.mem.Allocator, vm: *vm_mod.VM, uri: []const u8, text: []const u8) void {
    var diag_buf: std.ArrayList(u8) = .empty;
    defer diag_buf.deinit(allocator);
    diag_buf.append(allocator, '[') catch return;
    var has_diag = false;

    // Parse phase
    var r = reader.Reader.initWithName(vm.gc, text, uri);
    defer r.deinit();

    while (r.hasMore()) {
        const expr = r.readDatum() catch {
            const lc = r.getLineCol();
            if (has_diag) diag_buf.append(allocator, ',') catch {};
            has_diag = true;
            addDiagnostic(&diag_buf, allocator, @intCast(lc.line -| 1), 0, 1, "read error");
            break;
        };

        // Compile phase
        _ = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, &vm.globals, 0, uri) catch {
            const lc = r.getLineCol();
            if (has_diag) diag_buf.append(allocator, ',') catch {};
            has_diag = true;
            addDiagnostic(&diag_buf, allocator, @intCast(lc.line -| 1), 0, 1, "compile error");
            break;
        };
    }

    diag_buf.append(allocator, ']') catch return;

    // Build publishDiagnostics params
    var params_buf: std.ArrayList(u8) = .empty;
    defer params_buf.deinit(allocator);
    params_buf.appendSlice(allocator, "{\"uri\":") catch return;
    jsonString(&params_buf, allocator, uri);
    params_buf.appendSlice(allocator, ",\"diagnostics\":") catch return;
    params_buf.appendSlice(allocator, diag_buf.items) catch return;
    params_buf.append(allocator, '}') catch return;

    sendNotification(allocator, "textDocument/publishDiagnostics", params_buf.items);
}

fn addDiagnostic(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, line: u32, col: u32, severity: u8, message: []const u8) void {
    buf.appendSlice(allocator, "{\"range\":{\"start\":{\"line\":") catch return;
    jsonInt(buf, allocator, @intCast(line));
    buf.appendSlice(allocator, ",\"character\":") catch return;
    jsonInt(buf, allocator, @intCast(col));
    buf.appendSlice(allocator, "},\"end\":{\"line\":") catch return;
    jsonInt(buf, allocator, @intCast(line));
    buf.appendSlice(allocator, ",\"character\":999}},\"severity\":") catch return;
    jsonInt(buf, allocator, @intCast(severity));
    buf.appendSlice(allocator, ",\"source\":\"kaappi\",\"message\":") catch return;
    jsonString(buf, allocator, message);
    buf.append(allocator, '}') catch return;
}

// ---- Text position helpers ----

fn getSymbolAtPosition(text: []const u8, line: u32, col: u32) []const u8 {
    const offset = lineColToOffset(text, line, col);
    if (offset == 0) return "";
    // Scan backwards to find symbol start
    var start = offset;
    while (start > 0 and isSymbolChar(text[start - 1])) : (start -= 1) {}
    return text[start..offset];
}

fn getFullSymbolAtPosition(text: []const u8, line: u32, col: u32) []const u8 {
    const offset = lineColToOffset(text, line, col);
    var start = offset;
    while (start > 0 and isSymbolChar(text[start - 1])) : (start -= 1) {}
    var end = offset;
    while (end < text.len and isSymbolChar(text[end])) : (end += 1) {}
    return text[start..end];
}

fn lineColToOffset(text: []const u8, line: u32, col: u32) usize {
    var cur_line: u32 = 0;
    var i: usize = 0;
    while (i < text.len and cur_line < line) : (i += 1) {
        if (text[i] == '\n') cur_line += 1;
    }
    const target = i + @as(usize, col);
    return @min(target, text.len);
}

fn isSymbolChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or ch == '-' or ch == '_' or
        ch == '!' or ch == '?' or ch == '*' or ch == '+' or
        ch == '/' or ch == '<' or ch == '>' or ch == '=' or
        ch == '.' or ch == ':';
}

// ---- Main ----

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    const allocator = std.heap.c_allocator;

    log("kaappi-lsp v" ++ version ++ " starting\n");

    documents = std.StringHashMap([]const u8).init(allocator);
    doc_allocator = allocator;

    // Initialize GC, VM, and register primitives
    var gc = memory.GC.init(allocator);
    defer gc.deinit();
    var vm = try vm_mod.VM.init(&gc);
    defer vm.deinit();
    try primitives.registerAll(&vm);
    primitives.setGCInstance(&gc);
    try library.registerStandardLibraries(&vm.libraries, &vm.globals);

    var initialized = false;

    // Message loop
    while (true) {
        const msg = readMessage(allocator) orelse break;
        defer allocator.free(msg);

        const method = jsonGetString(msg, "method") orelse continue;
        const id = jsonGetInt(msg, "id");

        if (std.mem.eql(u8, method, "initialize")) {
            handleInitialize(allocator, id orelse 0);
            initialized = true;
        } else if (std.mem.eql(u8, method, "initialized")) {
            // Notification, no response needed
        } else if (std.mem.eql(u8, method, "shutdown")) {
            sendResponse(allocator, id orelse 0, "null");
        } else if (std.mem.eql(u8, method, "exit")) {
            break;
        } else if (!initialized) {
            if (id) |req_id| {
                sendResponse(allocator, req_id, "{\"code\":-32002,\"message\":\"not initialized\"}");
            }
        } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            handleDidOpenOrChange(allocator, &vm, msg);
        } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
            handleDidOpenOrChange(allocator, &vm, msg);
        } else if (std.mem.eql(u8, method, "textDocument/didClose")) {
            if (jsonGetObject(msg, "textDocument")) |td| {
                if (jsonGetString(td, "uri")) |uri| {
                    removeDocument(uri);
                    // Clear diagnostics
                    var pbuf: std.ArrayList(u8) = .empty;
                    defer pbuf.deinit(allocator);
                    pbuf.appendSlice(allocator, "{\"uri\":") catch continue;
                    jsonString(&pbuf, allocator, uri);
                    pbuf.appendSlice(allocator, ",\"diagnostics\":[]}") catch continue;
                    sendNotification(allocator, "textDocument/publishDiagnostics", pbuf.items);
                }
            }
        } else if (std.mem.eql(u8, method, "textDocument/completion")) {
            handleCompletion(allocator, &vm, id orelse 0, msg);
        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            handleHover(allocator, &vm, id orelse 0, msg);
        } else if (std.mem.eql(u8, method, "textDocument/documentSymbol")) {
            handleDocumentSymbol(allocator, &vm, id orelse 0, msg);
        }
    }

    log("kaappi-lsp exiting\n");
}
