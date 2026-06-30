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
fn jsonGetStringRaw(json: []const u8, key: []const u8) ?[]const u8 {
    var search_buf: [256]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;
    const pos = std.mem.indexOf(u8, json, search) orelse return null;
    var i = pos + search.len;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len or json[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < json.len and json[i] != '"') : (i += 1) {
        if (json[i] == '\\') {
            i += 1;
            if (i >= json.len) return null;
        }
    }
    return json[start..i];
}

fn jsonUnescape(allocator: std.mem.Allocator, raw: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, raw, '\\') == null) return raw;
    const buf = allocator.alloc(u8, raw.len) catch return null;
    var out: usize = 0;
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            i += 1;
            buf[out] = switch (raw[i]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '"' => '"',
                '\\' => '\\',
                '/' => '/',
                'b' => 0x08,
                'f' => 0x0C,
                else => raw[i],
            };
            out += 1;
        } else {
            buf[out] = raw[i];
            out += 1;
        }
        i += 1;
    }
    return buf[0..out];
}

fn jsonGetString(json: []const u8, key: []const u8) ?[]const u8 {
    return jsonGetStringRaw(json, key);
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

fn jsonGetRawId(json: []const u8) ?[]const u8 {
    var search_buf: [256]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"id\"", .{}) catch return null;
    const pos = std.mem.indexOf(u8, json, search) orelse return null;
    var i = pos + search.len;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t')) : (i += 1) {}
    if (i >= json.len) return null;
    if (json[i] == '"') {
        // String id — include quotes
        const start = i;
        i += 1;
        while (i < json.len) : (i += 1) {
            if (json[i] == '\\') {
                i += 1;
                continue;
            }
            if (json[i] == '"') return json[start .. i + 1];
        }
        return null;
    }
    // Numeric id
    const start = i;
    if (json[i] == '-') i += 1;
    while (i < json.len and json[i] >= '0' and json[i] <= '9') : (i += 1) {}
    if (i == start) return null;
    return json[start..i];
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
        if (json[i] == '"') {
            i += 1;
            while (i < json.len and json[i] != '"') : (i += 1) {
                if (json[i] == '\\') i += 1;
            }
        } else if (json[i] == '{') {
            depth += 1;
        } else if (json[i] == '}') {
            depth -= 1;
            if (depth == 0) return json[start .. i + 1];
        }
    }
    return null;
}

// ---- LSP message I/O ----

fn readMessage(allocator: std.mem.Allocator) ?[]u8 {
    var header_buf: [4096]u8 = undefined;
    var header_len: usize = 0;
    var content_length: usize = 0;
    var last4: [4]u8 = .{ 0, 0, 0, 0 };

    // Read headers until blank line
    while (true) {
        var byte: [1]u8 = undefined;
        const n = std.posix.read(0, &byte) catch return null;
        if (n == 0) return null;
        if (header_len < header_buf.len) {
            header_buf[header_len] = byte[0];
        }
        header_len += 1;
        last4[0] = last4[1];
        last4[1] = last4[2];
        last4[2] = last4[3];
        last4[3] = byte[0];
        if (header_len >= 4 and std.mem.eql(u8, &last4, "\r\n\r\n")) {
            // Parse Content-Length
            const hdr_end = @min(header_len, header_buf.len);
            const headers = header_buf[0..hdr_end];
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

fn sendResponse(allocator: std.mem.Allocator, id: []const u8, result: []const u8) void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":") catch return;
    buf.appendSlice(allocator, id) catch return;
    buf.appendSlice(allocator, ",\"result\":") catch return;
    buf.appendSlice(allocator, result) catch return;
    buf.append(allocator, '}') catch return;
    writeMessage(allocator, buf.items);
}

fn sendError(allocator: std.mem.Allocator, id: []const u8, code: i64, message: []const u8) void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":") catch return;
    buf.appendSlice(allocator, id) catch return;
    buf.appendSlice(allocator, ",\"error\":{\"code\":") catch return;
    jsonInt(&buf, allocator, code);
    buf.appendSlice(allocator, ",\"message\":") catch return;
    jsonString(&buf, allocator, message);
    buf.appendSlice(allocator, "}}") catch return;
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

fn getArity(val: types.Value, buf: *[32]u8) ?[]const u8 {
    if (!types.isPointer(val)) return null;
    const obj = types.toObject(val);
    if (obj.tag == .native_fn) {
        const nfn = obj.as(types.NativeFn);
        return switch (nfn.arity) {
            .exact => |n| std.fmt.bufPrint(buf, "{d}", .{n}) catch null,
            .variadic => |n| std.fmt.bufPrint(buf, "{d}+", .{n}) catch null,
        };
    }
    if (obj.tag == .closure) {
        const cls = obj.as(types.Closure);
        return std.fmt.bufPrint(buf, "{d}", .{cls.func.arity}) catch null;
    }
    return null;
}

// ---- LSP handlers ----

fn handleInitialize(allocator: std.mem.Allocator, id: []const u8) void {
    sendResponse(allocator, id,
        \\{"capabilities":{"positionEncoding":"utf-8","textDocumentSync":1,"completionProvider":{"resolveProvider":false,"triggerCharacters":[]},"hoverProvider":true,"documentSymbolProvider":true,"definitionProvider":true,"referencesProvider":true},"serverInfo":{"name":"kaappi-lsp","version":"0.1.0"}}
    );
}

fn handleCompletion(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: []const u8, params: []const u8) void {
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

fn handleHover(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: []const u8, params: []const u8) void {
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

    var arity_buf: [32]u8 = undefined;
    if (getArity(val, &arity_buf)) |arity| {
        md.appendSlice(allocator, "\\n\\nArity: ") catch {};
        md.appendSlice(allocator, arity) catch {};
    }

    jsonString(&buf, allocator, md.items);
    buf.appendSlice(allocator, "}}") catch {};
    sendResponse(allocator, id, buf.items);
}

fn handleDocumentSymbol(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: []const u8, params: []const u8) void {
    const td = jsonGetObject(params, "textDocument") orelse "";
    const uri = jsonGetString(td, "uri") orelse "";
    const text = getDocument(uri) orelse "";

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    result.append(allocator, '[') catch return;
    var first = true;

    var r = reader.Reader.init(vm.gc, text);
    defer r.deinit();

    while (r.hasMore() catch false) {
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
            result.appendSlice(allocator, "{\"name\":") catch {};
            jsonString(&result, allocator, n);
            result.appendSlice(allocator, ",\"kind\":") catch {};
            jsonInt(&result, allocator, kind);
            result.appendSlice(allocator, ",\"location\":{\"uri\":") catch {};
            jsonString(&result, allocator, uri);
            result.appendSlice(allocator, ",\"range\":{\"start\":{\"line\":") catch {};
            jsonInt(&result, allocator, line);
            result.appendSlice(allocator, ",\"character\":0},\"end\":{\"line\":") catch {};
            jsonInt(&result, allocator, line);
            result.appendSlice(allocator, ",\"character\":0}}}}") catch {};
        }
    }

    result.append(allocator, ']') catch return;
    sendResponse(allocator, id, result.items);
}

fn handleDefinition(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: []const u8, params: []const u8) void {
    const td = jsonGetObject(params, "textDocument") orelse "";
    const uri = jsonGetString(td, "uri") orelse "";
    const pos_obj = jsonGetObject(params, "position") orelse "";
    const line = jsonGetInt(pos_obj, "line") orelse 0;
    const character = jsonGetInt(pos_obj, "character") orelse 0;

    const text = getDocument(uri) orelse {
        sendResponse(allocator, id, "null");
        return;
    };

    const symbol = getFullSymbolAtPosition(text, @intCast(line), @intCast(character));
    if (symbol.len == 0) {
        sendResponse(allocator, id, "null");
        return;
    }

    var r = reader.Reader.init(vm.gc, text);
    defer r.deinit();

    while (r.hasMore() catch false) {
        const lc = r.getLineCol();
        const expr = r.readDatum() catch break;
        if (findDefineLocation(expr, symbol, lc.line)) |def_line| {
            const resp_line: i64 = @as(i64, @intCast(def_line)) - 1;
            var resp: std.ArrayList(u8) = .empty;
            defer resp.deinit(allocator);
            resp.appendSlice(allocator, "{\"uri\":") catch {};
            jsonString(&resp, allocator, uri);
            resp.appendSlice(allocator, ",\"range\":{\"start\":{\"line\":") catch {};
            jsonInt(&resp, allocator, resp_line);
            resp.appendSlice(allocator, ",\"character\":0},\"end\":{\"line\":") catch {};
            jsonInt(&resp, allocator, resp_line);
            resp.appendSlice(allocator, ",\"character\":0}}}") catch {};
            sendResponse(allocator, id, resp.items);
            return;
        }
    }

    sendResponse(allocator, id, "null");
}

fn findDefineLocation(expr: types.Value, name: []const u8, form_line: u32) ?u32 {
    if (!types.isPair(expr)) return null;
    const head = types.car(expr);
    if (!types.isSymbol(head)) return null;
    const form = types.symbolName(head);

    if (std.mem.eql(u8, form, "define")) {
        const rest = types.cdr(expr);
        if (rest == types.NIL) return null;
        const target = types.car(rest);
        if (types.isSymbol(target) and std.mem.eql(u8, types.symbolName(target), name)) {
            return form_line;
        }
        if (types.isPair(target)) {
            const fn_name = types.car(target);
            if (types.isSymbol(fn_name) and std.mem.eql(u8, types.symbolName(fn_name), name)) {
                return form_line;
            }
        }
    } else if (std.mem.eql(u8, form, "define-syntax") or std.mem.eql(u8, form, "define-record-type")) {
        const rest = types.cdr(expr);
        if (rest != types.NIL and types.isPair(rest)) {
            const def_name = types.car(rest);
            if (types.isSymbol(def_name) and std.mem.eql(u8, types.symbolName(def_name), name)) {
                return form_line;
            }
        }
    }
    return null;
}

fn handleReferences(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: []const u8, params: []const u8) void {
    _ = vm;
    const td = jsonGetObject(params, "textDocument") orelse "";
    const uri = jsonGetString(td, "uri") orelse "";
    const pos_obj = jsonGetObject(params, "position") orelse "";
    const line = jsonGetInt(pos_obj, "line") orelse 0;
    const character = jsonGetInt(pos_obj, "character") orelse 0;

    const text = getDocument(uri) orelse {
        sendResponse(allocator, id, "[]");
        return;
    };

    const symbol = getFullSymbolAtPosition(text, @intCast(line), @intCast(character));
    if (symbol.len == 0) {
        sendResponse(allocator, id, "[]");
        return;
    }

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    result.append(allocator, '[') catch return;
    var first = true;

    var cur_line: u32 = 0;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '\n') {
            cur_line += 1;
            i += 1;
            continue;
        }

        if (isSymbolChar(text[i])) {
            const start = i;
            var col: u32 = 0;
            var j = i;
            while (j > 0 and text[j - 1] != '\n') : (j -= 1) {
                col += 1;
            }
            while (i < text.len and isSymbolChar(text[i])) : (i += 1) {}
            const word = text[start..i];
            if (std.mem.eql(u8, word, symbol)) {
                if (!first) result.append(allocator, ',') catch {};
                first = false;
                const end_col = col + @as(u32, @intCast(word.len));
                result.appendSlice(allocator, "{\"uri\":") catch {};
                jsonString(&result, allocator, uri);
                result.appendSlice(allocator, ",\"range\":{\"start\":{\"line\":") catch {};
                jsonInt(&result, allocator, @intCast(cur_line));
                result.appendSlice(allocator, ",\"character\":") catch {};
                jsonInt(&result, allocator, @intCast(col));
                result.appendSlice(allocator, "},\"end\":{\"line\":") catch {};
                jsonInt(&result, allocator, @intCast(cur_line));
                result.appendSlice(allocator, ",\"character\":") catch {};
                jsonInt(&result, allocator, @intCast(end_col));
                result.appendSlice(allocator, "}}}") catch {};
            }
            continue;
        }

        if (text[i] == '"') {
            i += 1;
            while (i < text.len) {
                if (text[i] == '\\' and i + 1 < text.len) {
                    i += 2;
                } else if (text[i] == '"') {
                    i += 1;
                    break;
                } else {
                    if (text[i] == '\n') cur_line += 1;
                    i += 1;
                }
            }
            continue;
        }

        if (text[i] == ';') {
            while (i < text.len and text[i] != '\n') : (i += 1) {}
            continue;
        }

        i += 1;
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

    if (text) |raw_t| {
        const t = jsonUnescape(allocator, raw_t) orelse raw_t;
        defer if (t.ptr != raw_t.ptr) allocator.free(t);
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

    while (r.hasMore() catch false) {
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
        const id = jsonGetRawId(msg);

        if (std.mem.eql(u8, method, "initialize")) {
            handleInitialize(allocator, id orelse "0");
            initialized = true;
        } else if (std.mem.eql(u8, method, "initialized")) {
            // Notification, no response needed
        } else if (std.mem.eql(u8, method, "shutdown")) {
            sendResponse(allocator, id orelse "0", "null");
        } else if (std.mem.eql(u8, method, "exit")) {
            break;
        } else if (!initialized) {
            if (id) |req_id| {
                sendError(allocator, req_id, -32002, "not initialized");
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
            handleCompletion(allocator, &vm, id orelse "0", msg);
        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            handleHover(allocator, &vm, id orelse "0", msg);
        } else if (std.mem.eql(u8, method, "textDocument/documentSymbol")) {
            handleDocumentSymbol(allocator, &vm, id orelse "0", msg);
        } else if (std.mem.eql(u8, method, "textDocument/definition")) {
            handleDefinition(allocator, &vm, id orelse "0", msg);
        } else if (std.mem.eql(u8, method, "textDocument/references")) {
            handleReferences(allocator, &vm, id orelse "0", msg);
        }
    }

    log("kaappi-lsp exiting\n");
}

test "jsonGetRawId parses integer id" {
    const msg = "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"initialize\"}";
    const id = jsonGetRawId(msg);
    try std.testing.expect(id != null);
    try std.testing.expectEqualStrings("42", id.?);
}

test "jsonGetRawId parses string id" {
    const msg = "{\"jsonrpc\":\"2.0\",\"id\":\"req-1\",\"method\":\"initialize\"}";
    const id = jsonGetRawId(msg);
    try std.testing.expect(id != null);
    try std.testing.expectEqualStrings("\"req-1\"", id.?);
}

test "jsonGetRawId returns null for missing id" {
    const msg = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\"}";
    try std.testing.expect(jsonGetRawId(msg) == null);
}

test "jsonGetRawId parses negative id" {
    const msg = "{\"jsonrpc\":\"2.0\",\"id\":-1,\"method\":\"shutdown\"}";
    const id = jsonGetRawId(msg);
    try std.testing.expect(id != null);
    try std.testing.expectEqualStrings("-1", id.?);
}
