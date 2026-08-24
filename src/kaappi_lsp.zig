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
pub const check = @import("check.zig");
pub const check_lint = @import("check_lint.zig");

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

/// Validate that `params` is an object usable by a request method: it must carry
/// a `textDocument` object with a string `uri`, and (when `needs_position`) a
/// `position` object. Returns the params map on success, null otherwise — the
/// caller answers null with `-32602` InvalidParams rather than silently dropping
/// the request and leaving the client waiting on that id forever (kaappi#1980).
fn requestParams(params: ?std.json.ObjectMap, needs_position: bool) ?std.json.ObjectMap {
    const p = params orelse return null;
    const td = getObjField(p, "textDocument") orelse return null;
    if (getStrField(td, "uri") == null) return null;
    if (needs_position and getObjField(p, "position") == null) return null;
    return p;
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
                // A non-numeric Content-Length corrupts only this frame's own
                // framing. Return an empty (unparseable) body so the caller
                // skips it instead of ending the whole session; the next
                // readMessage then re-reads the leftover bytes and best-effort
                // resynchronises on the next `Content-Length` header (a body
                // that itself contains that literal can still mislead the
                // resync) (kaappi#1980).
                content_length = std.fmt.parseInt(usize, headers[cl_start..cl_end], 10) catch {
                    return allocator.alloc(u8, 0) catch return null;
                };
            }
            break;
        }
    }

    // A missing or zero Content-Length frames no body; return an empty,
    // unparseable body so the session continues rather than ending (kaappi#1980).
    if (content_length == 0) return allocator.alloc(u8, 0) catch return null;

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
            .range => |r| if (r.min == r.max)
                std.fmt.bufPrint(buf, "{d}", .{r.min}) catch null
            else
                std.fmt.bufPrint(buf, "{d}..{d}", .{ r.min, r.max }) catch null,
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
    // global not present at startup. Without this, `(import (mylib))` in one
    // document would leave its exports resolvable while diagnosing another that
    // imports nothing. Compilation never depends on a global's *value* here so
    // diagnostics were already correct, but hover/completion leaked across
    // documents and the asymmetry with the macro reset was surprising.
    //
    // Because this runs at the *start* of every diagnostics run, one shared
    // `vm.globals` means a document's imported names resolve for hover/completion
    // only until another document is opened or edited, self-healing on that
    // document's next run. That is the intended, bounded behaviour (matching the
    // per-document macro reset) — strictly better than the pre-change state where
    // imported names resolved nowhere — not a bug to chase into per-document
    // environments.
    pruneImportedGlobals(vm, allocator);

    // Resolve library and `include` paths against the document's own directory
    // when the URI is a `file://` URI, matching `kaappi check`. Two distinct
    // mechanisms, both restored after the run: `include` consults
    // `current_lib_dir` (with a trailing slash), while an `(import (lib))` of a
    // sibling `.sld` is resolved through `vm.lib_paths` — which never consults
    // `current_lib_dir` — so the document's directory must be prepended there
    // too, exactly as `main.zig` seeds the file's directory for `kaappi check`.
    // `path_buf` backs the decoded path for the whole run; the slices below
    // point into it, so it must outlive them (it does — it is this frame's).
    const saved_lib_dir = vm.current_lib_dir;
    const saved_lib_paths = vm.lib_paths;
    defer {
        vm.current_lib_dir = saved_lib_dir;
        vm.lib_paths = saved_lib_paths;
    }
    var path_buf: [2048]u8 = undefined;
    var lib_paths_run: [8][]const u8 = undefined;
    if (fileUriToPath(uri, &path_buf)) |doc_path| {
        if (std.mem.lastIndexOfScalar(u8, doc_path, '/')) |pos| {
            vm.current_lib_dir = doc_path[0 .. pos + 1];
            // Prepend the document's directory (no trailing slash, like
            // main.zig) ahead of the auto-discovered paths, capacity permitting.
            const dir = if (pos == 0) doc_path[0..1] else doc_path[0..pos];
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

    // Diagnose the document by driving the exact analysis `kaappi check` runs —
    // read + env-setup + compile + KP4xxx lint — into a `check_lint.Context`,
    // then serialize every finding through the shared LSP `Diagnostic` writer.
    // Sharing the analysis (not just the serializer) is what makes the LSP agree
    // with `kaappi check --diagnostics=json` on codes, severities, and spans
    // (kaappi#1981): a whole-file read error, every failing form, every KP4xxx
    // lint, and the real character range all reach the editor.
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var user_defined = std.StringHashMap(void).init(arena);
    check.collectTopLevelDefines(&user_defined, arena, vm.gc, text);

    var ctx: check_lint.Context = .{ .arena = arena, .user_defined = &user_defined };
    check.analyzeSource(vm, &ctx, text, uri);

    // Serialize every finding through the shared LSP `Diagnostic` writer into an
    // allocating writer (no fixed buffer), exactly as `check.zig`'s `reportJson`
    // does, so an arbitrarily long finding message is emitted rather than
    // silently dropped. The comma separator is appended only after a finding has
    // serialized successfully, so a finding that fails to serialize can never
    // leave a `[,` or `,]` that would corrupt the whole array (kaappi#1981 review).
    var aw: std.Io.Writer.Allocating = .init(arena);
    defer aw.deinit();

    diag_buf.append(allocator, '[') catch return;
    var first = true;
    for (ctx.findings.items) |finding| {
        aw.clearRetainingCapacity();
        var cbuf: [diagnostics.Code.render_width]u8 = undefined;
        const diag: lsp_diagnostic.Diagnostic = .{
            .range = lsp_diagnostic.spanRange(finding.span),
            .severity = lsp_diagnostic.severityOf(finding.code.info().severity),
            .code = finding.code.render(&cbuf),
            .message = finding.message,
        };
        diag.writeJson(&aw.writer) catch continue;
        if (!first) diag_buf.append(allocator, ',') catch return;
        diag_buf.appendSlice(allocator, aw.written()) catch return;
        first = false;
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
// across documents. The write lock `importBinding` also takes is held across the
// whole operation — iteration, key collection, and removal — so a concurrent
// child-thread reader (#958) never observes a half-pruned map; `global_version`
// is bumped to invalidate any cached global lookups. Keys are collected before
// removing (mutating a map mid-iteration is unsound) into a list; the collected
// slices point at externally-owned strings, so they stay valid across removal.
// Nothing in the loop re-acquires `globals_lock`, so holding it cannot deadlock.
fn pruneImportedGlobals(vm: *vm_mod.VM, allocator: std.mem.Allocator) void {
    vm.globals_lock.lock();
    defer vm.globals_lock.unlock();
    var to_remove: std.ArrayList([]const u8) = .empty;
    defer to_remove.deinit(allocator);
    var it = vm.globals.iterator();
    while (it.next()) |entry| {
        if (!baseline_global_keys.contains(entry.key_ptr.*))
            to_remove.append(allocator, entry.key_ptr.*) catch return;
    }
    if (to_remove.items.len == 0) return;
    for (to_remove.items) |k| _ = vm.globals.remove(k);
    vm.global_version +%= 1;
}

// Convert a `file://` URI to a native filesystem path in `buf`, percent-decoding
// `%XX` escapes and handling an empty or `localhost` authority and a Windows
// drive-letter path (`file:///C:/x` -> `C:/x`). Returns null for a non-`file:`
// URI (an editor may send `untitled:`/`vscode-vfs:` — no on-disk directory to
// resolve against) or when the decoded path does not fit `buf`. Not exhaustive
// URL parsing: only what document paths need so `include`/import resolution
// matches the real paths `kaappi check` sees (baijum review, coderabbit review).
fn fileUriToPath(uri: []const u8, buf: []u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, uri, "file://")) return null;
    var rest = uri["file://".len..];
    // Authority runs up to the next '/'. Accept only empty (`file:///…`) or
    // `localhost`; a real remote host has no local path to offer.
    if (rest.len > 0 and rest[0] != '/') {
        const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
        if (!std.mem.eql(u8, rest[0..slash], "localhost")) return null;
        rest = rest[slash..];
    }
    var n: usize = 0;
    var i: usize = 0;
    while (i < rest.len) {
        var c = rest[i];
        if (c == '%' and i + 2 < rest.len) {
            const hi = std.fmt.charToDigit(rest[i + 1], 16) catch 0xff;
            const lo = std.fmt.charToDigit(rest[i + 2], 16) catch 0xff;
            if (hi != 0xff and lo != 0xff) {
                c = @intCast(hi * 16 + lo);
                i += 3;
            } else i += 1; // malformed escape: keep the '%' literally
        } else i += 1;
        if (n >= buf.len) return null;
        buf[n] = c;
        n += 1;
    }
    var path = buf[0..n];
    // `file:///C:/x` decodes to `/C:/x`; drop the slash before the drive letter.
    if (path.len >= 3 and path[0] == '/' and path[2] == ':' and
        ((path[1] >= 'A' and path[1] <= 'Z') or (path[1] >= 'a' and path[1] <= 'z')))
        path = path[1..];
    return path;
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
// buffer is reused, never growing across the server's lifetime. This covers
// Scheme-level output only; a C-FFI library that writes to fd 1 directly during
// its load still bypasses it — a residual edge, not closed here because guarding
// it means redirecting fd 1 at the OS level (dup2), which is platform-specific
// and risks the framing if a restore is ever missed.
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
    // `i` is the start of the requested line (or `text.len` when the line is
    // past the end). Clamp `col` to the line's own length — up to its newline —
    // so a column past end-of-line stops at the line end rather than walking
    // into a later line (kaappi#1980).
    var line_end = i;
    while (line_end < text.len and text[line_end] != '\n') : (line_end += 1) {}
    return i + @min(col, line_end - i);
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
    var shutdown_requested = false;

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

        // Format the request id for response splicing. JSON-RPC ids are integers
        // or strings; anything else (null, a float, an array, an object) is an
        // Invalid Request answered with id null — never a fabricated id
        // (kaappi#1980).
        var id_buf: std.ArrayList(u8) = .empty;
        defer id_buf.deinit(allocator);
        var id_valid = false;
        if (root.get("id")) |id_val| {
            id_valid = formatIdValue(&id_buf, allocator, id_val);
        }
        const id: ?[]const u8 = if (id_valid) id_buf.items else null;

        // A request whose id we cannot echo is answered immediately with an
        // Invalid Request (id null) and never dispatched.
        if (root.get("id") != null and !id_valid) {
            sendError(allocator, "null", -32600, "Invalid Request");
            continue;
        }

        const params: ?std.json.ObjectMap = if (root.get("params")) |p|
            switch (p) {
                .object => |o| o,
                else => null,
            }
        else
            null;

        if (std.mem.eql(u8, method, "initialize")) {
            if (shutdown_requested) {
                if (id) |req_id| sendError(allocator, req_id, -32600, "Invalid Request");
            } else if (id) |req_id| {
                // An initialize sent as a notification (no id) gets no reply —
                // never a fabricated id 0 — and does not complete the handshake.
                handleInitialize(allocator, req_id);
                initialized = true;
            }
        } else if (std.mem.eql(u8, method, "initialized")) {
            // Notification, no response needed
        } else if (std.mem.eql(u8, method, "shutdown")) {
            if (!initialized) {
                if (id) |req_id| sendError(allocator, req_id, -32002, "not initialized");
            } else {
                if (id) |req_id| sendResponse(allocator, req_id, "null");
                shutdown_requested = true;
            }
        } else if (std.mem.eql(u8, method, "exit")) {
            // LSP 3.17: exit without a prior shutdown must be status 1, so a
            // supervising client can tell a clean shutdown from a crash-exit.
            if (shutdown_requested) break;
            log("kaappi-lsp exiting without shutdown\n");
            std.process.exit(1);
        } else if (!initialized) {
            if (id) |req_id| sendError(allocator, req_id, -32002, "not initialized");
        } else if (shutdown_requested) {
            // LSP 3.17: every request received after shutdown except `exit` is
            // an Invalid Request (-32600).
            if (id) |req_id| sendError(allocator, req_id, -32600, "Invalid Request");
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
            if (requestParams(params, true)) |p| {
                if (id) |req_id| handleCompletion(allocator, &vm, req_id, p);
            } else if (id) |req_id| {
                sendError(allocator, req_id, -32602, "InvalidParams");
            }
        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            if (requestParams(params, true)) |p| {
                if (id) |req_id| handleHover(allocator, &vm, req_id, p);
            } else if (id) |req_id| {
                sendError(allocator, req_id, -32602, "InvalidParams");
            }
        } else if (std.mem.eql(u8, method, "textDocument/documentSymbol")) {
            if (requestParams(params, false)) |p| {
                if (id) |req_id| handleDocumentSymbol(allocator, &vm, req_id, p);
            } else if (id) |req_id| {
                sendError(allocator, req_id, -32602, "InvalidParams");
            }
        } else if (std.mem.eql(u8, method, "textDocument/definition")) {
            if (requestParams(params, true)) |p| {
                if (id) |req_id| handleDefinition(allocator, &vm, req_id, p);
            } else if (id) |req_id| {
                sendError(allocator, req_id, -32602, "InvalidParams");
            }
        } else if (std.mem.eql(u8, method, "textDocument/references")) {
            if (requestParams(params, true)) |p| {
                if (id) |req_id| handleReferences(allocator, &vm, req_id, p);
            } else if (id) |req_id| {
                sendError(allocator, req_id, -32602, "InvalidParams");
            }
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
