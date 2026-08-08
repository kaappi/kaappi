const std = @import("std");
const platform = @import("platform.zig");
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
pub const vm_library = @import("vm_library.zig");
pub const kaappi_paths = @import("kaappi_paths.zig");
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
pub const diagnostics = @import("diagnostics.zig");
pub const lsp_diagnostic = @import("lsp_diagnostic.zig");

const version = "0.1.0";
const initialize_result =
    "{\"capabilities\":{\"textDocumentSync\":1,\"completionProvider\":{\"resolveProvider\":false,\"triggerCharacters\":[]},\"hoverProvider\":true,\"documentSymbolProvider\":true,\"definitionProvider\":true,\"referencesProvider\":true},\"serverInfo\":{\"name\":\"kaappi-lsp\",\"version\":\"" ++ version ++ "\"}}";

fn log(msg: []const u8) void {
    _ = platform.write(2, msg.ptr, msg.len);
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

fn getObjField(obj: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .object => |o| o,
        else => null,
    };
}

fn getStrField(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

fn getIntField(obj: std.json.ObjectMap, key: []const u8) ?i64 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .integer => |n| n,
        else => null,
    };
}

fn formatIdValue(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, id_val: std.json.Value) bool {
    switch (id_val) {
        .integer => |n| {
            jsonInt(buf, allocator, n);
            return true;
        },
        .string => |s| {
            jsonString(buf, allocator, s);
            return true;
        },
        else => return false,
    }
}

fn clampToU32(val: i64) u32 {
    if (val < 0) return 0;
    if (val > std.math.maxInt(u32)) return std.math.maxInt(u32);
    return @intCast(@as(u64, @bitCast(val)));
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
        const n = platform.read(0, &byte, 1);
        if (n < 0) {
            if (platform.errno(n) == .INTR) continue;
            return null;
        }
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
        const n = platform.read(0, body.ptr + total, content_length - total);
        if (n < 0) {
            if (platform.errno(n) == .INTR) continue;
            allocator.free(body);
            return null;
        }
        if (n == 0) {
            allocator.free(body);
            return null;
        }
        total += @intCast(n);
    }
    return body;
}

/// Writes the whole slice, retrying short writes and EINTR: a partial
/// LSP header or payload desynchronizes the JSON-RPC framing for every
/// later message, so give up on the frame only on a hard write error.
fn writeAll(fd: platform.fd_t, bytes: []const u8) bool {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const n = platform.write(fd, bytes.ptr + offset, bytes.len - offset);
        if (n < 0) {
            if (platform.errno(n) == .INTR) continue;
            return false;
        }
        if (n == 0) return false;
        offset += @intCast(n);
    }
    return true;
}

fn writeMessage(allocator: std.mem.Allocator, json: []const u8) void {
    var header: [64]u8 = undefined;
    const h = std.fmt.bufPrint(&header, "Content-Length: {d}\r\n\r\n", .{json.len}) catch return;
    if (!writeAll(1, h)) return;
    _ = writeAll(1, json);
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

/// Snapshot of `vm.macros` taken after startup, before any document is opened.
/// Every `runDiagnostics` run resets the shared `vm.macros` back to this
/// baseline, so a `define-syntax` in one open document can never change how
/// any other document is diagnosed (kaappi#1979). Values are rooted via
/// `gc.extra_roots` at snapshot time: they are referenced only by this table
/// from the moment a document shadows one of their names until the next run
/// re-seeds `vm.macros` from it. Keys are interned symbol names, owned by the
/// GC's symbol table, so the snapshot never owns them.
var baseline_macros: std.StringHashMap(types.Value) = undefined;

/// The auto-discovered library search paths set up at startup (`~/.kaappi/lib`
/// plus the exe-relative fallback). `runDiagnostics` prepends the current
/// document's own directory to these for the duration of a run — mirroring how
/// `main.zig` seeds `vm.lib_paths` with the file's directory — so an `(import
/// (mylib))` resolves a `.sld` sitting next to the document, exactly as
/// `kaappi check` does. Points into the process-lifetime allocation `main`
/// makes; never mutated after startup.
var base_lib_paths: []const []const u8 = &.{};

/// The set of global names present after startup, before any document is
/// diagnosed. `runDiagnostics` removes any global *not* in this set at the start
/// of each run, retracting the value bindings a previous document's `import`
/// wrote into `vm.globals` — the globals-map analogue of the `vm.macros` reset
/// above, so imported names cannot leak across documents (only `vm.macros` was
/// isolated before). Keys are interned/static names the map does not own, so the
/// snapshot never owns them either.
var baseline_global_keys: std.StringHashMap(void) = undefined;

/// A single in-memory output port that discards everything written to it.
/// `runDiagnostics` redirects the VM's current-output-port to this while it runs
/// a document's `import`/`include`/`define-library` forms for their effect, so a
/// stray top-level `(display ...)` in executed library or included code cannot
/// write to fd 1 and corrupt the JSON-RPC frame stream. Its buffer is truncated
/// to empty before each run so it never grows across the server's lifetime.
var diag_sink_port: types.Value = types.VOID;

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

const getTypeName = types.typeName;

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
    sendResponse(allocator, id, initialize_result);
}

fn handleCompletion(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: []const u8, params: std.json.ObjectMap) void {
    const td = getObjField(params, "textDocument") orelse return;
    const uri = getStrField(td, "uri") orelse return;
    const pos = getObjField(params, "position") orelse return;
    const line = getIntField(pos, "line") orelse 0;
    const character = getIntField(pos, "character") orelse 0;

    const text = getDocument(uri) orelse "";
    const prefix = getSymbolAtPosition(text, clampToU32(line), clampToU32(character));

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

fn handleHover(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: []const u8, params: std.json.ObjectMap) void {
    const td = getObjField(params, "textDocument") orelse return;
    const uri = getStrField(td, "uri") orelse return;
    const pos = getObjField(params, "position") orelse return;
    const line = getIntField(pos, "line") orelse 0;
    const character = getIntField(pos, "character") orelse 0;

    const text = getDocument(uri) orelse "";
    const symbol = getFullSymbolAtPosition(text, clampToU32(line), clampToU32(character));

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
        md.appendSlice(allocator, "\n\nArity: ") catch {};
        md.appendSlice(allocator, arity) catch {};
    }

    jsonString(&buf, allocator, md.items);
    buf.appendSlice(allocator, "}}") catch {};
    sendResponse(allocator, id, buf.items);
}

fn handleDocumentSymbol(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: []const u8, params: std.json.ObjectMap) void {
    const td = getObjField(params, "textDocument") orelse return;
    const uri = getStrField(td, "uri") orelse return;
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
            if (rest == types.NIL or !types.isPair(rest)) continue;
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

fn handleDefinition(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: []const u8, params: std.json.ObjectMap) void {
    const td = getObjField(params, "textDocument") orelse return;
    const uri = getStrField(td, "uri") orelse return;
    const pos = getObjField(params, "position") orelse return;
    const line = getIntField(pos, "line") orelse 0;
    const character = getIntField(pos, "character") orelse 0;

    const text = getDocument(uri) orelse {
        sendResponse(allocator, id, "null");
        return;
    };

    const symbol = getFullSymbolAtPosition(text, clampToU32(line), clampToU32(character));
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
        if (rest == types.NIL or !types.isPair(rest)) return null;
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

fn handleReferences(allocator: std.mem.Allocator, vm: *vm_mod.VM, id: []const u8, params: std.json.ObjectMap) void {
    _ = vm;
    const td = getObjField(params, "textDocument") orelse return;
    const uri = getStrField(td, "uri") orelse return;
    const pos = getObjField(params, "position") orelse return;
    const line = getIntField(pos, "line") orelse 0;
    const character = getIntField(pos, "character") orelse 0;

    const text = getDocument(uri) orelse {
        sendResponse(allocator, id, "[]");
        return;
    };

    const symbol = getFullSymbolAtPosition(text, clampToU32(line), clampToU32(character));
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

fn handleDidOpenOrChange(allocator: std.mem.Allocator, vm: *vm_mod.VM, params: std.json.ObjectMap) void {
    const td = getObjField(params, "textDocument") orelse return;
    const uri = getStrField(td, "uri") orelse return;

    // For didOpen, text is in textDocument.text
    // For didChange (full sync), text is in contentChanges[0].text
    var text: ?[]const u8 = getStrField(td, "text");

    if (text == null) {
        if (params.get("contentChanges")) |cc_val| {
            switch (cc_val) {
                .array => |arr| {
                    if (arr.items.len > 0) {
                        switch (arr.items[0]) {
                            .object => |change_obj| {
                                text = getStrField(change_obj, "text");
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
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

    // Reset the shared macro table to the pre-document baseline: each document
    // is diagnosed as if it were the only one open. The define-syntax forms
    // compiled below accumulate in `vm.macros` across the document's own
    // forms — the same top-to-bottom visibility `kaappi check` gives a
    // standalone file — but nothing survives to another document, so byte-
    // identical text gets the same verdict regardless of what else is open
    // (kaappi#1979). Values written here are marked by the VM's GC exactly as
    // before; they are simply retracted by the next run's reset.
    vm.macros.clearRetainingCapacity();
    var mit = baseline_macros.iterator();
    while (mit.next()) |entry| {
        vm.macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return;
    }

    // Retract the value bindings a previous document's `import` left in
    // `vm.globals` (the globals analogue of the macro reset above): remove every
    // global not present at startup. Without this, `(import (srfi 1))` in one
    // document would leave `fold` etc. resolvable while diagnosing another that
    // imports nothing. Compilation never depends on a global's *value* here so
    // diagnostics were already correct, but hover/completion leaked across
    // documents and the asymmetry with the macro reset was surprising. Held
    // under the same write lock `importBinding` uses, with a `global_version`
    // bump so any cached global lookups are invalidated.
    pruneImportedGlobals(vm, allocator);

    // Resolve library and `include` paths against the document's own directory
    // when the URI is a `file://` URI, matching `kaappi check`. Two distinct
    // mechanisms, both restored after the run: `include` consults
    // `current_lib_dir` (with a trailing slash), while an `(import (lib))` of a
    // sibling `.sld` is resolved through `vm.lib_paths` — which never consults
    // `current_lib_dir` — so the document's directory must be prepended there
    // too, exactly as `main.zig` seeds the file's directory for `kaappi check`.
    const saved_lib_dir = vm.current_lib_dir;
    const saved_lib_paths = vm.lib_paths;
    defer {
        vm.current_lib_dir = saved_lib_dir;
        vm.lib_paths = saved_lib_paths;
    }
    var lib_paths_run: [8][]const u8 = undefined;
    if (std.mem.startsWith(u8, uri, "file://")) {
        const p = uri["file://".len..];
        if (std.mem.lastIndexOfScalar(u8, p, '/')) |pos| {
            vm.current_lib_dir = p[0 .. pos + 1];
            // Prepend the document's directory (no trailing slash, like
            // main.zig) ahead of the auto-discovered paths, capacity permitting.
            const dir = if (pos == 0) p[0..1] else p[0..pos];
            if (base_lib_paths.len + 1 <= lib_paths_run.len) {
                lib_paths_run[0] = dir;
                @memcpy(lib_paths_run[1 .. base_lib_paths.len + 1], base_lib_paths);
                vm.lib_paths = lib_paths_run[0 .. base_lib_paths.len + 1];
            }
        }
    }

    // Redirect the current-output-port to a discard sink for the run so a stray
    // top-level `(display ...)` in executed env-setup code (an imported library
    // body, an included file) cannot write to fd 1 and corrupt the JSON-RPC
    // framing. Restored after the run.
    const out_redirect = beginOutputRedirect(vm);
    defer endOutputRedirect(vm, out_redirect);

    // Parse phase
    var r = reader.Reader.initWithName(vm.gc, text, uri);
    defer r.deinit();

    while (r.hasMore() catch false) {
        var expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            if (has_diag) diag_buf.append(allocator, ',') catch {};
            has_diag = true;
            addDiagnostic(&diag_buf, allocator, lc.line -| 1, diagnostics.readErrorCode(err));
            break;
        };

        // The reader sits just past the form now; this is the same line the
        // original compile-only loop reported, so the cross-check against
        // `kaappi check` (tests/scheme/lsp/lsp.sh §4) still agrees.
        const line0 = r.getLineCol().line -| 1;
        vm.gc.pushRoot(&expr);
        const stop = diagnoseTopLevelForm(&diag_buf, allocator, vm, uri, expr, line0, &has_diag);
        vm.gc.popRoot();
        // The server publishes only the first failing form's diagnostic
        // (kaappi#1980, deliberately covered in the LSP suite).
        if (stop) break;
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

// Remove every global not present at startup — the value bindings a previous
// document's `import` wrote into `vm.globals` — so imported names do not leak
// across documents. Keys are collected first (mutating a map mid-iteration is
// unsound), then removed under the write lock `importBinding` also takes, with a
// `global_version` bump to invalidate any cached global lookups. The collected
// key slices point at externally-owned strings, so they stay valid across the
// removals.
fn pruneImportedGlobals(vm: *vm_mod.VM, allocator: std.mem.Allocator) void {
    var to_remove: std.ArrayList([]const u8) = .empty;
    defer to_remove.deinit(allocator);
    var it = vm.globals.iterator();
    while (it.next()) |entry| {
        if (!baseline_global_keys.contains(entry.key_ptr.*))
            to_remove.append(allocator, entry.key_ptr.*) catch return;
    }
    if (to_remove.items.len == 0) return;
    vm.globals_lock.lock();
    defer vm.globals_lock.unlock();
    for (to_remove.items) |k| _ = vm.globals.remove(k);
    vm.global_version +%= 1;
}

// State captured by beginOutputRedirect so endOutputRedirect can restore it.
const OutputRedirect = struct {
    active: bool,
    saved_stdout_port: types.Value,
    param: types.Value,
    saved_param_val: types.Value,
};

// Point the VM's current-output-port at the discard sink for the duration of a
// diagnostics run. `display`/`write` resolve the port through
// `current_output_port_param` first, falling back to `vm.stdout_port`, so both
// are redirected. The sink's write cursor and length are reset first so its
// buffer is reused, never growing across the server's lifetime.
fn beginOutputRedirect(vm: *vm_mod.VM) OutputRedirect {
    if (diag_sink_port == types.VOID)
        return .{ .active = false, .saved_stdout_port = types.VOID, .param = types.VOID, .saved_param_val = types.VOID };
    const port = types.toObject(diag_sink_port).as(types.Port);
    port.string_out_pos = 0;
    port.string_out_len = 0;
    var rd: OutputRedirect = .{
        .active = true,
        .saved_stdout_port = vm.stdout_port,
        .param = vm.current_output_port_param,
        .saved_param_val = types.VOID,
    };
    vm.stdout_port = diag_sink_port;
    if (rd.param != types.VOID) {
        rd.saved_param_val = vm.getParameterValue(types.toParameter(rd.param));
        vm.setParameterValue(types.toParameter(rd.param), diag_sink_port) catch {};
    }
    return rd;
}

fn endOutputRedirect(vm: *vm_mod.VM, rd: OutputRedirect) void {
    if (!rd.active) return;
    vm.stdout_port = rd.saved_stdout_port;
    if (rd.param != types.VOID)
        vm.setParameterValue(types.toParameter(rd.param), rd.saved_param_val) catch {};
}

// Diagnose one top-level form, returning true when it recorded a diagnostic
// (the caller then stops — the server publishes only the first, kaappi#1980).
//
// The classification mirrors `check.zig`'s `checkForm`, sharing the very
// `TopLevelHead` machinery `kaappi check` and the runtime use so the three
// cannot drift (kaappi#2114): a top-level `begin` and the selected `cond-expand`
// clause splice into the top-level sequence and are recursed into, the
// environment-establishing heads (`import`/`define-library`/`include`/
// `define-record-type`) are *run* for their effect so later forms see the
// bindings and macros they introduce, and everything else is compiled but not
// executed. Running imports is what makes an imported macro like SRFI 42's
// `list-ec` expand — without it, the compiler judges the `(if test)` filter
// qualifier inside the comprehension as a malformed one-armed R7RS `if` and
// flags valid code.
fn diagnoseTopLevelForm(
    diag_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    vm: *vm_mod.VM,
    uri: []const u8,
    expr: types.Value,
    line0: u32,
    has_diag: *bool,
) bool {
    if (types.isPair(expr) and types.isSymbol(types.car(expr))) {
        if (vm.topLevelHead(expr)) |head| {
            switch (head) {
                // R7RS 5.1: top-level `begin` splices its body as top-level
                // forms — recurse so a nested import runs for its effect.
                .begin => {
                    var rest = types.cdr(expr);
                    while (types.isPair(rest)) : (rest = types.cdr(rest)) {
                        if (diagnoseTopLevelForm(diag_buf, allocator, vm, uri, types.car(rest), line0, has_diag)) return true;
                    }
                    return false;
                },
                // R7RS 4.2.1: a top-level `cond-expand` splices its selected
                // clause's body as top-level forms. Clause selection uses the
                // same evaluator the runtime does, so both pick the same clause.
                .cond_expand => {
                    var clauses = types.cdr(expr);
                    while (types.isPair(clauses)) : (clauses = types.cdr(clauses)) {
                        const clause = types.car(clauses);
                        if (!types.isPair(clause)) break;
                        const req = types.car(clause);
                        const is_else = types.isSymbol(req) and std.mem.eql(u8, types.symbolName(req), "else");
                        if (is_else or vm_library.evalLibFeatureReq(vm, req)) {
                            var body = types.cdr(clause);
                            while (types.isPair(body)) : (body = types.cdr(body)) {
                                if (diagnoseTopLevelForm(diag_buf, allocator, vm, uri, types.car(body), line0, has_diag)) return true;
                            }
                            return false;
                        }
                    }
                    // No clause matched: fall through and compile it as an
                    // expression (the compiler folds a no-match to void), the
                    // same fallback check.zig and the runtime compiler take.
                },
                else => {
                    if (head.isEnvSetup()) {
                        _ = vm.runTopLevelHead(head, expr) catch |err| {
                            const code = if (vm.last_error_code != .uncategorized)
                                vm.last_error_code
                            else
                                diagnostics.runtimeErrorCode(err);
                            recordDiagnostic(diag_buf, allocator, line0, code, has_diag);
                            vm.last_error_detail_len = 0;
                            vm.last_error_code = .uncategorized;
                            return true;
                        };
                        return false;
                    }
                    // define-values: only its names matter, never its producer's
                    // effect — fall through to compile-not-run, like check.zig.
                },
            }
        }
    }

    // Everything else — define, define-syntax, define-values, expressions — is
    // compiled (registering any define-syntax macro and surfacing compile
    // errors) but never executed. The compiled Function is discarded.
    _ = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, 0, uri, false) catch |err| {
        recordDiagnostic(diag_buf, allocator, line0, diagnostics.compileErrorCode(err), has_diag);
        return true;
    };
    return false;
}

// Append one diagnostic to the array under construction, inserting the JSON
// comma separator before all but the first.
fn recordDiagnostic(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, line0: u32, code: diagnostics.Code, has_diag: *bool) void {
    if (has_diag.*) buf.append(allocator, ',') catch {};
    has_diag.* = true;
    addDiagnostic(buf, allocator, line0, code);
}

// Serialize one diagnostic through the shared LSP `Diagnostic` writer
// (src/lsp_diagnostic.zig) — the same code path `--diagnostics=json` uses, so
// the CLI and the server can never drift (kaappi#1505). The range spans the
// whole line (character 0..999) to highlight it in an editor; the `code` is the
// stable KP code and `message` its registry template.
fn addDiagnostic(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, line0: u32, code: diagnostics.Code) void {
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    const diag: lsp_diagnostic.Diagnostic = .{
        .range = .{
            .start = .{ .line = line0, .character = 0 },
            .end = .{ .line = line0, .character = 999 },
        },
        .severity = lsp_diagnostic.severityOf(code.info().severity),
        .code = code.render(&cbuf),
        .message = code.message(),
    };
    var tmp: [1024]u8 = undefined;
    var w: std.Io.Writer = .fixed(&tmp);
    diag.writeJson(&w) catch return;
    buf.appendSlice(allocator, w.buffered()) catch return;
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

    // Byte-faithful stdio (Windows): the LSP wire format is length-framed,
    // so CRT text-mode \n→\r\n rewriting on fd 1 would corrupt framing.
    platform.initStandardStreams();

    // The LSP compiles user code on this (main) thread — unlike the kaappi
    // binary, which runs on a 64 MB worker thread — so on OpenBSD it must
    // raise its own 4 MiB default stack limit to avoid overflowing on deeply
    // nested forms. No-op elsewhere. See docs/dev/openbsd.md.
    platform.raiseStackLimitBestEffort();
    platform.normalizeFpEnvBestEffort();

    log("kaappi-lsp v" ++ version ++ " starting\n");

    documents = std.StringHashMap([]const u8).init(allocator);
    doc_allocator = allocator;

    // Initialize GC, VM, and register primitives
    var gc = memory.GC.init(allocator);
    defer gc.deinit();
    var vm = try vm_mod.VM.init(&gc);
    defer vm.deinit();
    vm_mod.setVMInstance(&vm);
    memory.setGCInstance(&gc);
    try primitives.registerAll(&vm);
    try vm_mod.vm_bootstrap.install(&vm);
    try library.registerStandardLibraries(&vm.libraries, vm.globals);

    // Resolve file-based `.sld` libraries (portable SRFIs, ecosystem packages)
    // the same way the `kaappi` binary does — otherwise `runDiagnostics`'
    // `(import (srfi 42))` fails to find the library and every use of an
    // imported macro is mis-diagnosed. The two auto-discovered
    // dirs mirror main.zig's setup, computed from the same `kaappi_paths`
    // helpers so they cannot drift: `~/.kaappi/lib` for an installed tree, and
    // `<exe_dir>/../lib` so a from-source `zig build` (no installer) still
    // resolves the bundled SRFI sources (#1523). These strings must outlive
    // every diagnostics run, so they come from the process-lifetime `allocator`
    // rather than a scratch buffer; the server owns them until it exits.
    var lib_paths_buf: [2][]const u8 = undefined;
    var lib_path_count: usize = 0;
    {
        var home_buf: [512]u8 = undefined;
        if (kaappi_paths.getHome(&home_buf)) |home| {
            const klp = std.fmt.allocPrint(allocator, "{s}/lib", .{home}) catch null;
            if (klp) |p| {
                lib_paths_buf[lib_path_count] = p;
                lib_path_count += 1;
            }
        }
        var exe_lib_buf: [1024]u8 = undefined;
        if (kaappi_paths.getExeRelativeLibDir(&exe_lib_buf)) |elp| {
            const dup = allocator.dupe(u8, elp) catch null;
            if (dup) |p| {
                lib_paths_buf[lib_path_count] = p;
                lib_path_count += 1;
            }
        }
    }
    vm.lib_paths = try allocator.dupe([]const u8, lib_paths_buf[0..lib_path_count]);
    base_lib_paths = vm.lib_paths;

    // Snapshot the macro table before any document is opened; runDiagnostics
    // resets the shared `vm.macros` to this per run (kaappi#1979). `vm.macros`
    // is empty here today, but the snapshot keeps the isolation correct if
    // startup ever seeds it (e.g. a pre-imported library). The baseline values
    // are rooted once via extra_roots — the GC cannot see this table, and the
    // VM's own macro marking covers vm.macros only.
    baseline_macros = std.StringHashMap(types.Value).init(gc.allocator);
    var mit = vm.macros.iterator();
    while (mit.next()) |entry| {
        baseline_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return;
        gc.extra_roots.append(gc.allocator, entry.value_ptr.*) catch return;
    }

    // Snapshot the global names present at startup so runDiagnostics can retract
    // whatever a document's `import` adds (the globals analogue of the macro
    // reset above). Keys are interned/static and outlive the map, so the set
    // only borrows them.
    baseline_global_keys = std.StringHashMap(void).init(gc.allocator);
    var git = vm.globals.iterator();
    while (git.next()) |entry| {
        baseline_global_keys.put(entry.key_ptr.*, {}) catch return;
    }

    // A discard port for side effects of executed env-setup forms (see the
    // field doc). Rooted for the process lifetime like the standard ports.
    diag_sink_port = gc.allocStringOutputPort() catch types.VOID;
    if (diag_sink_port != types.VOID) gc.extra_roots.append(gc.allocator, diag_sink_port) catch {};

    var initialized = false;

    // Message loop
    while (true) {
        const msg = readMessage(allocator) orelse break;
        defer allocator.free(msg);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, msg, .{}) catch continue;
        defer parsed.deinit();

        const root = switch (parsed.value) {
            .object => |o| o,
            else => continue,
        };

        const method = getStrField(root, "method") orelse continue;

        // Format id for response splicing (null for notifications)
        var id_buf: std.ArrayList(u8) = .empty;
        defer id_buf.deinit(allocator);
        if (root.get("id")) |id_val| {
            _ = formatIdValue(&id_buf, allocator, id_val);
        }
        const id: ?[]const u8 = if (id_buf.items.len > 0) id_buf.items else null;

        const params: ?std.json.ObjectMap = if (root.get("params")) |p|
            switch (p) {
                .object => |o| o,
                else => null,
            }
        else
            null;

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
        } else if (std.mem.eql(u8, method, "textDocument/didOpen") or
            std.mem.eql(u8, method, "textDocument/didChange"))
        {
            if (params) |p| handleDidOpenOrChange(allocator, &vm, p);
        } else if (std.mem.eql(u8, method, "textDocument/didClose")) {
            if (params) |po| {
                if (getObjField(po, "textDocument")) |td| {
                    if (getStrField(td, "uri")) |uri| {
                        removeDocument(uri);
                        var pbuf: std.ArrayList(u8) = .empty;
                        defer pbuf.deinit(allocator);
                        pbuf.appendSlice(allocator, "{\"uri\":") catch continue;
                        jsonString(&pbuf, allocator, uri);
                        pbuf.appendSlice(allocator, ",\"diagnostics\":[]}") catch continue;
                        sendNotification(allocator, "textDocument/publishDiagnostics", pbuf.items);
                    }
                }
            }
        } else if (std.mem.eql(u8, method, "textDocument/completion")) {
            if (params) |p| handleCompletion(allocator, &vm, id orelse "0", p);
        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            if (params) |p| handleHover(allocator, &vm, id orelse "0", p);
        } else if (std.mem.eql(u8, method, "textDocument/documentSymbol")) {
            if (params) |p| handleDocumentSymbol(allocator, &vm, id orelse "0", p);
        } else if (std.mem.eql(u8, method, "textDocument/definition")) {
            if (params) |p| handleDefinition(allocator, &vm, id orelse "0", p);
        } else if (std.mem.eql(u8, method, "textDocument/references")) {
            if (params) |p| handleReferences(allocator, &vm, id orelse "0", p);
        } else if (id != null) {
            sendError(allocator, id.?, -32601, "MethodNotFound");
        }
    }

    log("kaappi-lsp exiting\n");
}

test "formatIdValue formats integer id" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"jsonrpc":"2.0","id":42,"method":"initialize"}
    , .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try std.testing.expect(formatIdValue(&buf, std.testing.allocator, root.get("id").?));
    try std.testing.expectEqualStrings("42", buf.items);
}

test "formatIdValue formats string id" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"jsonrpc":"2.0","id":"req-1","method":"initialize"}
    , .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try std.testing.expect(formatIdValue(&buf, std.testing.allocator, root.get("id").?));
    try std.testing.expectEqualStrings("\"req-1\"", buf.items);
}

test "missing id returns null from object map" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"jsonrpc":"2.0","method":"initialized"}
    , .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try std.testing.expect(root.get("id") == null);
}

test "formatIdValue formats negative id" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"jsonrpc":"2.0","id":-1,"method":"shutdown"}
    , .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try std.testing.expect(formatIdValue(&buf, std.testing.allocator, root.get("id").?));
    try std.testing.expectEqualStrings("-1", buf.items);
}

test "getStrField extracts string values" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"method":"textDocument/hover","uri":"file:///test.scm"}
    , .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try std.testing.expectEqualStrings("textDocument/hover", getStrField(root, "method").?);
    try std.testing.expectEqualStrings("file:///test.scm", getStrField(root, "uri").?);
    try std.testing.expect(getStrField(root, "missing") == null);
}

test "getObjField extracts nested objects" {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"params":{"textDocument":{"uri":"file:///a.scm"},"position":{"line":5,"character":10}}}
    , .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    const p = getObjField(root, "params").?;
    const td = getObjField(p, "textDocument").?;
    try std.testing.expectEqualStrings("file:///a.scm", getStrField(td, "uri").?);
    const pos = getObjField(p, "position").?;
    try std.testing.expectEqual(@as(i64, 5), getIntField(pos, "line").?);
    try std.testing.expectEqual(@as(i64, 10), getIntField(pos, "character").?);
}
