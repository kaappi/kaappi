//! Heap object allocators, split out of memory.zig (file size policy).
//!
//! Every `allocXxx` constructor takes `self: *GC` as its first parameter and
//! is re-exported as a method alias inside `GC` (memory.zig), so call sites
//! keep using `gc.allocXxx(...)` unchanged. The allocation discipline lives
//! here: root Value arguments (rootArgs/slice_roots) before maybeCollect, and
//! copy caller-owned memory *before* collecting so a slice aliasing another
//! heap object's storage stays valid (#1401) — see .claude/rules/gc-safety.md.

const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
const types = @import("types.zig");
const diagnostics = @import("diagnostics.zig");
const shared_buffer = @import("shared_buffer.zig");
const instrument = @import("channel_instrument.zig");

const memory = @import("memory.zig");
const GC = memory.GC;
const spinLock = memory.spinLock;
const spinUnlock = memory.spinUnlock;
const allocSliceNoFill = memory.allocSliceNoFill;
const freeSliceNoFill = memory.freeSliceNoFill;
const dupeSliceNoFill = memory.dupeSliceNoFill;

const Value = types.Value;
const Object = types.Object;
const ObjectTag = types.ObjectTag;
const Pair = types.Pair;
const Symbol = types.Symbol;
const SchemeString = types.SchemeString;
const Closure = types.Closure;
const Function = types.Function;
const NativeFn = types.NativeFn;
const Flonum = types.Flonum;
const Transformer = types.Transformer;
const Vector = types.Vector;
const Bytevector = types.Bytevector;
const Promise = types.Promise;
const RecordType = types.RecordType;
const RecordInstance = types.RecordInstance;
const Port = types.Port;
const Continuation = types.Continuation;
const MultipleValues = types.MultipleValues;
const SavedFrame = types.SavedFrame;
const SavedHandler = types.SavedHandler;
const WindRecord = types.WindRecord;
const FfiLibrary = types.FfiLibrary;
const FfiFunction = types.FfiFunction;
const FfiCallback = types.FfiCallback;
const FfiType = types.FfiType;
const HashTable = types.HashTable;
const HashEntry = types.HashEntry;
const Bignum = types.Bignum;
const Rational = types.Rational;
const RandomSource = types.RandomSource;

pub fn allocPair(self: *GC, car_val: Value, cdr_val: Value) !Value {
    self.rootArgs2(car_val, cdr_val);
    try self.maybeCollect();
    self.clearArgRoots();
    const pair = try self.allocator.create(Pair);
    pair.* = .{
        .header = .{ .tag = .pair },
        .car = car_val,
        .cdr = cdr_val,
    };
    self.finishAlloc(&pair.header, @sizeOf(Pair));
    return types.makePointer(&pair.header);
}

pub fn allocSymbol(self: *GC, name: []const u8) !Value {
    // `is_child` means this GC aliases the parent's symbol table via
    // `shared_symbols`; the parent GC (shared_symbols == null) owns that
    // very table as its own `symbols` field. Both sides are therefore
    // concurrent readers/writers of one StringHashMap whenever an SRFI-18
    // child thread is alive, so the lock must be taken *unconditionally* —
    // not just by children. `StringHashMap.put` can rehash (realloc + free
    // of the bucket array), and an unlocked parent-side get/put racing a
    // child's locked access corrupts the map (issue #797).
    //
    // Deadlock-free by the same argument as gc_collect.zig markRoots (which
    // also takes symbol_mutex while iterating the table): allocSymbol never
    // calls maybeCollect, so a thread can never re-enter GC marking — which
    // acquires this same non-reentrant lock — while holding it here.
    const is_child = self.shared_symbols != null;
    const sym_table = self.shared_symbols orelse &self.symbols;

    spinLock(&memory.symbol_mutex);
    defer spinUnlock(&memory.symbol_mutex);

    if (sym_table.get(name)) |existing| return existing;

    const owned_name = try self.allocator.dupe(u8, name);
    const sym = try self.allocator.create(Symbol);
    sym.* = .{
        .header = .{ .tag = .symbol },
        .name = owned_name,
    };
    const size = @sizeOf(Symbol) + name.len;
    self.bytes_allocated += size;
    self.profileAlloc(size);

    if (is_child) {
        // The symbol lives in the parent's shared table and must outlive
        // this child thread, so hand ownership to the parent (freed at the
        // parent's deinit). Appended under `symbol_mutex`, held here.
        // `shared_foreign_symbols` is set whenever `shared_symbols` is.
        // Stamp the parent's id: the parent owns it, and the parent's
        // markRoots pass over the shared table must not skip it.
        sym.header.owner = self.shared_owner_id;
        self.shared_foreign_symbols.?.append(self.allocator, &sym.header) catch {
            self.allocator.destroy(sym);
            self.allocator.free(owned_name);
            return error.OutOfMemory;
        };
    } else {
        self.trackObject(&sym.header);
    }

    const val = types.makePointer(&sym.header);
    try sym_table.put(owned_name, val);
    return val;
}

/// SRFI 258: allocate an *uninterned* symbol. Unlike `allocSymbol`, this
/// never consults or inserts into the symbol table, so the result is a fresh
/// object that is never `eqv?` to any other symbol — including a like-named
/// interned symbol or another uninterned symbol with the same name. It is an
/// ordinary collectable heap object: the interned-symbol root scan
/// (gc_collect.markRoots) walks only the symbol table, so an uninterned
/// symbol is swept once unreachable and `freeObject` frees its name. Always
/// tracked in *this* GC, even on a child thread — an uninterned symbol is
/// never shared through the parent's intern table, and crossing a thread
/// boundary deep-copies it (gc_deep_copy) into the destination heap.
pub fn allocUninternedSymbol(self: *GC, name: []const u8) !Value {
    // Copy before collecting: `name` may point into another heap object
    // (e.g. a SchemeString's bytes) that this collection could free.
    const owned_name = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(owned_name);
    try self.maybeCollect();
    const sym = try self.allocator.create(Symbol);
    sym.* = .{
        .header = .{ .tag = .symbol },
        .name = owned_name,
        .interned = false,
    };
    self.finishAlloc(&sym.header, @sizeOf(Symbol) + name.len);
    return types.makePointer(&sym.header);
}

pub fn allocString(self: *GC, data: []const u8) !Value {
    // Copy before collecting: `data` may point into another heap object
    // (e.g. a SchemeString's bytes) that this collection could free.
    const owned = try dupeSliceNoFill(self.allocator, u8, data);
    errdefer freeSliceNoFill(self.allocator, u8, owned);
    try self.maybeCollect();
    const str = try self.allocator.create(SchemeString);
    str.* = .{
        .header = .{ .tag = .string },
        .data = owned,
        .len = data.len,
    };
    self.finishAlloc(&str.header, @sizeOf(SchemeString) + data.len);
    return types.makePointer(&str.header);
}

pub fn allocFunction(self: *GC) !*Function {
    const func = try self.allocator.create(Function);
    func.* = .{
        .header = .{ .tag = .function },
        .code = .empty,
        .constants = .empty,
        .arity = 0,
    };
    self.finishAlloc(&func.header, @sizeOf(Function));
    return func;
}

pub fn allocClosure(self: *GC, func: *Function) !Value {
    self.rootArgs1(types.makePointer(&func.header));
    try self.maybeCollect();
    self.clearArgRoots();
    const upvalue_count = func.upvalue_count;
    const upvalues = try allocSliceNoFill(self.allocator, Value, upvalue_count);
    errdefer freeSliceNoFill(self.allocator, Value, upvalues);
    @memset(upvalues, types.UNDEFINED);

    const cls = try self.allocator.create(Closure);
    cls.* = .{
        .header = .{ .tag = .closure },
        .func = func,
        .upvalues = upvalues,
    };
    self.finishAlloc(&cls.header, @sizeOf(Closure) + @as(usize, upvalue_count) * @sizeOf(Value));
    return types.makePointer(&cls.header);
}

pub fn allocNativeFn(self: *GC, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !Value {
    const nf = try self.allocator.create(NativeFn);
    nf.* = .{
        .header = .{ .tag = .native_fn },
        .func = func,
        .name = name,
        .arity = arity,
    };
    self.finishAlloc(&nf.header, @sizeOf(NativeFn));
    return types.makePointer(&nf.header);
}

pub fn allocNativeClosure(self: *GC, fn_ptr: types.NativeClosureFnType, upvalues: []const Value, arity: u8, name: []const u8) !Value {
    // Copy upvalues before collecting and root them across the collection
    // (see allocVector).
    const uv_copy = try dupeSliceNoFill(self.allocator, Value, upvalues);
    errdefer freeSliceNoFill(self.allocator, Value, uv_copy);
    const saved_slice_roots = self.slice_roots;
    self.slice_roots = uv_copy;
    defer self.slice_roots = saved_slice_roots;
    try self.maybeCollect();
    const nc = try self.allocator.create(types.NativeClosure);
    nc.* = .{
        .header = .{ .tag = .native_closure },
        .fn_ptr = fn_ptr,
        .upvalues = uv_copy,
        .arity = arity,
        .name = name,
    };
    self.finishAlloc(&nc.header, @sizeOf(types.NativeClosure) + upvalues.len * @sizeOf(Value));
    return types.makePointer(&nc.header);
}

pub fn allocFlonum(self: *GC, value: f64) !Value {
    _ = self;
    return types.makeFlonum(value);
}

pub fn allocVector(self: *GC, data: []const Value) !Value {
    // Copy before collecting (`data` may alias another vector's storage),
    // and root the copied values across the collection: callers routinely
    // pass freshly allocated Values held nowhere else.
    const owned = try dupeSliceNoFill(self.allocator, Value, data);
    errdefer freeSliceNoFill(self.allocator, Value, owned);
    const saved_slice_roots = self.slice_roots;
    self.slice_roots = owned;
    defer self.slice_roots = saved_slice_roots;
    try self.maybeCollect();
    const vec = try self.allocator.create(Vector);
    vec.* = .{
        .header = .{ .tag = .vector },
        .data = owned,
    };
    self.finishAlloc(&vec.header, @sizeOf(Vector) + data.len * @sizeOf(Value));
    return types.makePointer(&vec.header);
}

/// Upper bound for a single payload allocation (vector/bytevector/
/// string data), checked before asking the OS. Overcommitting
/// kernels (FreeBSD's default) will reserve an absurd request — a
/// 100 TB make-bytevector "succeeds" and the zero-fill then commits
/// pages until the kernel's OOM killer ends the process — so malloc
/// refusal cannot be the graceful heap-exhausted error path
/// (docs/dev/freebsd.md). 1 TiB is far beyond any real
/// mark-and-sweep heap while leaving every legitimate allocation
/// untouched. (On 32-bit targets usize can't express the limit;
/// clamping makes the guard a no-op there, which is correct — the
/// address space itself is the cap.)
pub const max_payload_bytes: usize = @min(1 << 40, std.math.maxInt(usize));

pub fn allocVectorFill(self: *GC, size: usize, fill: Value) !Value {
    if (size > max_payload_bytes / @sizeOf(Value)) return error.OutOfMemory;
    self.rootArgs1(fill);
    try self.maybeCollect();
    self.clearArgRoots();
    const data = try allocSliceNoFill(self.allocator, Value, size);
    errdefer freeSliceNoFill(self.allocator, Value, data);
    @memset(data, fill);
    const vec = try self.allocator.create(Vector);
    vec.* = .{
        .header = .{ .tag = .vector },
        .data = data,
    };
    self.finishAlloc(&vec.header, @sizeOf(Vector) + size * @sizeOf(Value));
    return types.makePointer(&vec.header);
}

pub fn allocErrorObject(self: *GC, message: Value, irritants: Value) !Value {
    return self.allocErrorObjectCoded(message, irritants, .uncategorized);
}

/// Like `allocErrorObject` but stamps a stable diagnostic code (KEP-0005).
/// Implementation raise sites that map to a specific registry code use this;
/// user errors and unmigrated sites use `allocErrorObject` (code
/// `.uncategorized`, which surfaces as the KP3000 "uncaught exception" code
/// at the top level).
pub fn allocErrorObjectCoded(self: *GC, message: Value, irritants: Value, code: diagnostics.Code) !Value {
    self.rootArgs2(message, irritants);
    try self.maybeCollect();
    self.clearArgRoots();
    const err = try self.allocator.create(types.ErrorObject);
    err.* = .{
        .header = .{ .tag = .error_object },
        .message = message,
        .irritants = irritants,
        .code = code,
    };
    self.finishAlloc(&err.header, @sizeOf(types.ErrorObject));
    return types.makePointer(&err.header);
}

pub fn allocTransformer(self: *GC, literals: []const Value, patterns: []const Value, templates: []const Value) !Value {
    const num_rules: u16 = @intCast(patterns.len);
    const owned_lits = try self.allocator.dupe(Value, literals);
    errdefer self.allocator.free(owned_lits);
    const owned_pats = try self.allocator.dupe(Value, patterns);
    errdefer self.allocator.free(owned_pats);
    const owned_tmps = try self.allocator.dupe(Value, templates);
    errdefer self.allocator.free(owned_tmps);

    const tx = try self.allocator.create(Transformer);
    tx.* = .{
        .header = .{ .tag = .transformer },
        .literals = owned_lits,
        .patterns = owned_pats,
        .templates = owned_tmps,
        .num_rules = num_rules,
    };
    self.finishAlloc(&tx.header, @sizeOf(Transformer) + (literals.len + patterns.len + templates.len) * @sizeOf(Value));
    return types.makePointer(&tx.header);
}

/// SRFI 211: a procedural (explicit-renaming or Lisp-style) macro
/// transformer wrapping a Scheme procedure. No rules — the expander
/// calls `proc` instead of pattern-matching (expandProceduralMacro).
/// The empty rule slices are shared static empties; freeObject's
/// zero-length frees on them are no-ops.
pub fn allocProceduralTransformer(self: *GC, kind: types.TransformerKind, proc: Value) !Value {
    self.rootArgs1(proc);
    try self.maybeCollect();
    self.clearArgRoots();
    const tx = try self.allocator.create(Transformer);
    tx.* = .{
        .header = .{ .tag = .transformer },
        .literals = &.{},
        .patterns = &.{},
        .templates = &.{},
        .num_rules = 0,
        .kind = kind,
        .proc = proc,
    };
    self.finishAlloc(&tx.header, @sizeOf(Transformer));
    return types.makePointer(&tx.header);
}

pub fn allocRecordType(self: *GC, name: []const u8, num_fields: u8) !Value {
    // Copy before collecting: `name` may alias a symbol/string's bytes.
    const owned_name = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(owned_name);
    try self.maybeCollect();
    const rt = try self.allocator.create(RecordType);
    rt.* = .{
        .header = .{ .tag = .record_type },
        .name = owned_name,
        .num_fields = num_fields,
    };
    self.finishAlloc(&rt.header, @sizeOf(RecordType) + name.len);
    return types.makePointer(&rt.header);
}

/// SRFI 237: a record type with inheritance (`parent`), per-field
/// metadata, and R6RS `nongenerative`/`sealed`/`opaque` attributes.
/// `field_names`/`field_mutable` describe this type's OWN fields only
/// (not inherited ones) -- `num_fields` on the result is the TOTAL
/// including everything inherited from `parent`, matching
/// RecordInstance.fields' layout (parent fields first, then own).
pub fn allocRecordTypeExtended(
    self: *GC,
    name: []const u8,
    parent: ?*RecordType,
    field_names: []const []const u8,
    field_mutable: []const bool,
    uid: ?[]const u8,
    sealed: bool,
    is_opaque: bool,
) !Value {
    // num_fields/own_field_count are u8 -- reject before any allocation
    // rather than let the @intCast below panic (ReleaseSafe) or wrap
    // (ReleaseFast) on a type with 256+ own fields, or fewer own fields
    // that still push the inherited total past 255.
    const parent_fields: u16 = if (parent) |p| p.num_fields else 0;
    if (field_names.len > 255 or parent_fields + field_names.len > 255) {
        return error.TooManyFields;
    }

    // Copy every owned byte range before collecting -- each may alias
    // a symbol/string's own bytes (see allocRecordType above).
    const owned_name = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(owned_name);

    const owned_field_names = try self.allocator.alloc([]const u8, field_names.len);
    var copied: usize = 0;
    errdefer {
        for (owned_field_names[0..copied]) |s| self.allocator.free(s);
        self.allocator.free(owned_field_names);
    }
    for (field_names, 0..) |fname, i| {
        owned_field_names[i] = try self.allocator.dupe(u8, fname);
        copied += 1;
    }

    const owned_field_mutable = try self.allocator.dupe(bool, field_mutable);
    errdefer self.allocator.free(owned_field_mutable);

    const owned_uid: ?[]const u8 = if (uid) |u| try self.allocator.dupe(u8, u) else null;
    errdefer if (owned_uid) |u| self.allocator.free(u);

    // `parent` is a live heap object (not owned bytes) -- root it,
    // since it's the one field here maybeCollect() could otherwise
    // reclaim if nothing else currently references it.
    if (parent) |p| self.rootArgs1(types.makePointer(&p.header)) else self.rootArgs1(types.FALSE);
    try self.maybeCollect();
    self.clearArgRoots();

    const own_count: u8 = @intCast(field_names.len);
    const total_fields: u16 = parent_fields + @as(u16, own_count);

    const rt = try self.allocator.create(RecordType);
    rt.* = .{
        .header = .{ .tag = .record_type },
        .name = owned_name,
        .num_fields = @intCast(total_fields),
        .own_field_count = own_count,
        .parent = parent,
        .own_field_names = owned_field_names,
        .own_field_mutable = owned_field_mutable,
        .uid = owned_uid,
        .sealed = sealed,
        .is_opaque = is_opaque,
    };

    var extra_bytes: usize = owned_field_names.len * @sizeOf([]const u8);
    for (owned_field_names) |s| extra_bytes += s.len;
    extra_bytes += owned_field_mutable.len * @sizeOf(bool);
    if (owned_uid) |u| extra_bytes += u.len;

    self.finishAlloc(&rt.header, @sizeOf(RecordType) + owned_name.len + extra_bytes);
    return types.makePointer(&rt.header);
}

pub fn allocRecordInstance(self: *GC, record_type: *RecordType, field_values: []const Value) !Value {
    // Copy the fields before collecting and root them (plus the record
    // type itself) across the collection (see allocVector).
    const fields = try allocSliceNoFill(self.allocator, Value, record_type.num_fields);
    errdefer freeSliceNoFill(self.allocator, Value, fields);
    for (0..record_type.num_fields) |i| {
        if (i < field_values.len) {
            fields[i] = field_values[i];
        } else {
            fields[i] = types.UNDEFINED;
        }
    }
    self.rootArgs1(types.makePointer(&record_type.header));
    const saved_slice_roots = self.slice_roots;
    self.slice_roots = fields;
    defer self.slice_roots = saved_slice_roots;
    try self.maybeCollect();
    self.clearArgRoots();
    const ri = try self.allocator.create(RecordInstance);
    ri.* = .{
        .header = .{ .tag = .record_instance },
        .record_type = record_type,
        .fields = fields,
    };
    self.finishAlloc(&ri.header, @sizeOf(RecordInstance) + record_type.num_fields * @sizeOf(Value));
    return types.makePointer(&ri.header);
}

pub fn allocPort(self: *GC, fd: platform.fd_t, is_input: bool, is_output: bool, name: []const u8, owns_name: bool) !Value {
    try self.maybeCollect();
    const port = try self.allocator.create(Port);
    port.* = .{
        .header = .{ .tag = .port },
        .fd = fd,
        .is_input = is_input,
        .is_output = is_output,
        .is_open = true,
        .name = name,
        .owns_name = owns_name,
        .peek_byte = null,
        .is_string_port = false,
        .string_data = null,
        .string_pos = 0,
        .string_out_buf = null,
        .string_out_len = 0,
        .string_out_cap = 0,
    };
    self.finishAlloc(&port.header, @sizeOf(Port));
    return types.makePointer(&port.header);
}

pub fn allocStringInputPort(self: *GC, data: []const u8) !Value {
    // Copy before collecting: `data` usually aliases a SchemeString.
    const owned = try self.allocator.dupe(u8, data);
    errdefer self.allocator.free(owned);
    try self.maybeCollect();
    const port = try self.allocator.create(Port);
    port.* = .{
        .header = .{ .tag = .port },
        .fd = -1,
        .is_input = true,
        .is_output = false,
        .is_open = true,
        .name = "string",
        .owns_name = false,
        .peek_byte = null,
        .is_string_port = true,
        .string_data = owned,
        .string_pos = 0,
    };
    self.finishAlloc(&port.header, @sizeOf(Port) + data.len);
    return types.makePointer(&port.header);
}

pub fn allocStringOutputPort(self: *GC) !Value {
    try self.maybeCollect();
    const initial_cap: usize = 64;
    const buf = try self.allocator.alloc(u8, initial_cap);
    errdefer self.allocator.free(buf);
    const port = try self.allocator.create(Port);
    port.* = .{
        .header = .{ .tag = .port },
        .fd = -1,
        .is_input = false,
        .is_output = true,
        .is_open = true,
        .name = "string",
        .owns_name = false,
        .peek_byte = null,
        .is_string_port = true,
        .string_out_buf = buf,
        .string_out_len = 0,
        .string_out_cap = initial_cap,
    };
    self.finishAlloc(&port.header, @sizeOf(Port) + initial_cap);
    return types.makePointer(&port.header);
}

/// SRFI 181: a port backed by user-supplied Scheme procedures. Up to 6
/// Values need protecting across the collection at once -- beyond
/// rootArgs2's 2-Value cap -- so this follows allocMultipleValues's
/// slice_roots template rather than rootArgs1/rootArgs2: point
/// slice_roots at a transient local array (it only needs to be valid
/// for the scan window, not to become the object's own storage) and
/// restore it before returning. Each *_proc is either a procedure or
/// types.FALSE ("absent"); callers validate procedure-ness before
/// calling this.
pub fn allocCustomPort(
    self: *GC,
    is_input: bool,
    is_output: bool,
    is_binary: bool,
    read_proc: Value,
    write_proc: Value,
    get_position_proc: Value,
    set_position_proc: Value,
    close_proc: Value,
    flush_proc: Value,
) !Value {
    var roots: [6]Value = .{ read_proc, write_proc, get_position_proc, set_position_proc, close_proc, flush_proc };
    const saved_slice_roots = self.slice_roots;
    self.slice_roots = &roots;
    defer self.slice_roots = saved_slice_roots;
    try self.maybeCollect();
    const cb = try self.allocator.create(types.CustomBacking);
    errdefer self.allocator.destroy(cb);
    cb.* = .{
        .read_proc = read_proc,
        .write_proc = write_proc,
        .get_position_proc = get_position_proc,
        .set_position_proc = set_position_proc,
        .close_proc = close_proc,
        .flush_proc = flush_proc,
    };
    const port = try self.allocator.create(Port);
    port.* = .{
        .header = .{ .tag = .port },
        .fd = -1,
        .is_input = is_input,
        .is_output = is_output,
        .is_open = true,
        .name = "custom",
        .owns_name = false,
        .peek_byte = null,
        .is_binary = is_binary,
        .custom_backend = cb,
    };
    self.finishAlloc(&port.header, @sizeOf(Port) + @sizeOf(types.CustomBacking));
    return types.makePointer(&port.header);
}

/// A SRFI 181 transcoded port: a textual view over `wrapped_port` (a
/// binary port) via `codec`/`eol_style`/`error_mode`. Only one Value
/// to protect across the collection (`wrapped_port` itself; the other
/// three are plain enums) -- rootArgs1, matching allocPair's shape,
/// rather than allocCustomPort's slice_roots (needed there for up to
/// 6 simultaneous Values).
pub fn allocTranscodedPort(
    self: *GC,
    wrapped_port: Value,
    is_input: bool,
    is_output: bool,
    codec: types.Codec,
    eol_style: types.EolStyle,
    error_mode: types.ErrorMode,
) !Value {
    self.rootArgs1(wrapped_port);
    try self.maybeCollect();
    self.clearArgRoots();
    const ts = try self.allocator.create(types.TranscodeState);
    errdefer self.allocator.destroy(ts);
    ts.* = .{
        .wrapped_port = wrapped_port,
        .codec = codec,
        .eol_style = eol_style,
        .error_mode = error_mode,
    };
    const port = try self.allocator.create(Port);
    port.* = .{
        .header = .{ .tag = .port },
        .fd = -1,
        .is_input = is_input,
        .is_output = is_output,
        .is_open = true,
        .name = "transcoded",
        .owns_name = false,
        .peek_byte = null,
        .is_binary = false,
        .transcode = ts,
    };
    self.finishAlloc(&port.header, @sizeOf(Port) + @sizeOf(types.TranscodeState));
    return types.makePointer(&port.header);
}

/// A SRFI-271 random binary input port backed by `gen` (copied to the
/// heap and owned by the port; freed in gc_collect's port sweep). No fd,
/// no string buffer — reads come from gen.nextByte() via readOneByte.
pub fn allocRandomPort(self: *GC, gen: types.RandomGen) !Value {
    try self.maybeCollect();
    const g = try self.allocator.create(types.RandomGen);
    g.* = gen;
    errdefer self.allocator.destroy(g);
    const port = try self.allocator.create(Port);
    port.* = .{
        .header = .{ .tag = .port },
        .fd = -1,
        .is_input = true,
        .is_output = false,
        .is_open = true,
        .name = "random",
        .owns_name = false,
        .peek_byte = null,
        .is_string_port = false,
        .is_binary = true,
        .random_gen = g,
    };
    self.finishAlloc(&port.header, @sizeOf(Port) + @sizeOf(types.RandomGen));
    return types.makePointer(&port.header);
}

pub fn allocBytevector(self: *GC, data: []const u8) !Value {
    // Copy before collecting: `data` may alias another bytevector/string.
    const owned = try dupeSliceNoFill(self.allocator, u8, data);
    errdefer freeSliceNoFill(self.allocator, u8, owned);
    try self.maybeCollect();
    const bv = try self.allocator.create(Bytevector);
    bv.* = .{
        .header = .{ .tag = .bytevector },
        .data = owned,
    };
    self.finishAlloc(&bv.header, @sizeOf(Bytevector) + data.len);
    return types.makePointer(&bv.header);
}

pub fn allocBytevectorFill(self: *GC, size: usize, fill: u8) !Value {
    if (size > max_payload_bytes) return error.OutOfMemory;
    try self.maybeCollect();
    const data = try allocSliceNoFill(self.allocator, u8, size);
    errdefer freeSliceNoFill(self.allocator, u8, data);
    @memset(data, fill);
    const bv = try self.allocator.create(Bytevector);
    bv.* = .{
        .header = .{ .tag = .bytevector },
        .data = data,
    };
    self.finishAlloc(&bv.header, @sizeOf(Bytevector) + size);
    return types.makePointer(&bv.header);
}

/// SRFI 160. `data` must already be `elements * kind.elementWidth()`
/// bytes, correctly encoded -- callers (primitives_srfi160.zig) build the
/// byte buffer themselves since encoding is Value-type-dependent.
pub fn allocNumericVector(self: *GC, kind: types.NumericElementKind, data: []const u8) !Value {
    const owned = try dupeSliceNoFill(self.allocator, u8, data);
    errdefer freeSliceNoFill(self.allocator, u8, owned);
    try self.maybeCollect();
    const nv = try self.allocator.create(types.NumericVector);
    nv.* = .{
        .header = .{ .tag = .numeric_vector },
        .kind = kind,
        .data = owned,
    };
    self.finishAlloc(&nv.header, @sizeOf(types.NumericVector) + data.len);
    return types.makePointer(&nv.header);
}

/// `fill_bytes` is one already-encoded element (`kind.elementWidth()`
/// bytes), repeated `elements` times -- callers encode the fill Value
/// once, same division of labor as allocNumericVector.
pub fn allocNumericVectorFill(self: *GC, kind: types.NumericElementKind, elements: usize, fill_bytes: []const u8) !Value {
    const width = kind.elementWidth();
    std.debug.assert(fill_bytes.len == width);
    if (elements > max_payload_bytes / width) return error.OutOfMemory;
    const size = elements * width;
    try self.maybeCollect();
    const data = try allocSliceNoFill(self.allocator, u8, size);
    errdefer freeSliceNoFill(self.allocator, u8, data);
    var i: usize = 0;
    while (i < elements) : (i += 1) {
        @memcpy(data[i * width ..][0..width], fill_bytes);
    }
    const nv = try self.allocator.create(types.NumericVector);
    nv.* = .{
        .header = .{ .tag = .numeric_vector },
        .kind = kind,
        .data = data,
    };
    self.finishAlloc(&nv.header, @sizeOf(types.NumericVector) + size);
    return types.makePointer(&nv.header);
}

/// Lever D (kaappi#1472): a bytevector whose bytes are BORROWED from a
/// refcounted immutable `shared_buffer.SharedBuffer` rather than owned.
/// `bytes` must be `shared`'s own slice; this object stores the pointer and
/// does not copy or free the bytes (freeObject releases the reference
/// instead). The caller owns the reference this object will hold
/// (SharedBuffer.create's rc=1, or a retain()) -- following allocChannelStub,
/// allocate first so a failure here leaves the caller's reference intact to
/// drop, rather than leaking it on a retain that precedes a failed alloc.
pub fn allocBytevectorShared(self: *GC, shared: *anyopaque, bytes: []u8) !Value {
    try self.maybeCollect();
    const bv = try self.allocator.create(Bytevector);
    bv.* = .{
        .header = .{ .tag = .bytevector },
        .data = bytes,
        .shared = shared,
    };
    // The bytes live in the SharedBuffer, not this heap: count only the
    // struct, so the per-heap footprint reflects lever D's whole point.
    self.finishAlloc(&bv.header, @sizeOf(Bytevector));
    return types.makePointer(&bv.header);
}

/// Lever D copy-on-write (kaappi#1472): if `bv` borrows a shared immutable
/// buffer, give it private ownership of a copy and drop the shared reference
/// BEFORE it is mutated -- so a writer never touches shared bytes and
/// Scheme's copy semantics hold. No-op for an ordinary owned bytevector (and
/// comptime-pruned entirely in the shipped build, where none are ever
/// backed). Not under any collection here: the dupe is a raw allocator call
/// and callers run outside deepCopy's no_collect region.
pub fn unshareBytevector(self: *GC, bv: *Bytevector) !void {
    if (comptime !instrument.enabled) return;
    if (bv.shared) |raw| {
        const owned = try self.allocator.dupe(u8, bv.data);
        bv.data = owned;
        bv.shared = null;
        self.bytes_allocated += owned.len;
        const sb: *shared_buffer.SharedBuffer = @ptrCast(@alignCast(raw));
        sb.release();
    }
}

pub fn allocPromise(self: *GC, forced: bool, value: Value) !Value {
    self.rootArgs1(value);
    try self.maybeCollect();
    self.clearArgRoots();
    const p = try self.allocator.create(Promise);
    p.* = .{
        .header = .{ .tag = .promise },
        .forced = forced,
        .value = value,
    };
    self.finishAlloc(&p.header, @sizeOf(Promise));
    return types.makePointer(&p.header);
}

pub fn allocContinuation(
    self: *GC,
    registers: []const Value,
    frames: []const SavedFrame,
    frame_count: usize,
    handlers: []const SavedHandler,
    handler_count: usize,
    wind_records: []const WindRecord,
    wind_count: usize,
    dst_reg: u16,
    dst_base: u32,
) !Value {
    try self.maybeCollect();

    // Pack the four saved arrays into one backing allocation. Every element
    // type is a multiple of Value's size and no more strictly aligned than
    // Value, so a []Value buffer is correctly aligned for each section and
    // each section begins on a Value boundary.
    comptime {
        std.debug.assert(@sizeOf(SavedFrame) % @sizeOf(Value) == 0);
        std.debug.assert(@sizeOf(SavedHandler) % @sizeOf(Value) == 0);
        std.debug.assert(@sizeOf(WindRecord) % @sizeOf(Value) == 0);
        std.debug.assert(@alignOf(SavedFrame) <= @alignOf(Value));
        std.debug.assert(@alignOf(SavedHandler) <= @alignOf(Value));
        std.debug.assert(@alignOf(WindRecord) <= @alignOf(Value));
    }
    const frame_words = frames.len * (@sizeOf(SavedFrame) / @sizeOf(Value));
    const handler_words = handlers.len * (@sizeOf(SavedHandler) / @sizeOf(Value));
    const wind_words = wind_records.len * (@sizeOf(WindRecord) / @sizeOf(Value));
    const total_words = registers.len + frame_words + handler_words + wind_words;

    const backing = try allocSliceNoFill(self.allocator, Value, total_words);
    errdefer freeSliceNoFill(self.allocator, Value, backing);

    var off: usize = 0;
    const saved_regs = backing[off..][0..registers.len];
    off += registers.len;
    const frames_ptr: [*]SavedFrame = @ptrCast(@alignCast(backing.ptr + off));
    const saved_frames = frames_ptr[0..frames.len];
    off += frame_words;
    const handlers_ptr: [*]SavedHandler = @ptrCast(@alignCast(backing.ptr + off));
    const saved_handlers = handlers_ptr[0..handlers.len];
    off += handler_words;
    const winds_ptr: [*]WindRecord = @ptrCast(@alignCast(backing.ptr + off));
    const saved_winds = winds_ptr[0..wind_records.len];

    @memcpy(saved_regs, registers);
    @memcpy(saved_frames, frames);
    @memcpy(saved_handlers, handlers);
    @memcpy(saved_winds, wind_records);

    const cont = try self.allocator.create(Continuation);
    cont.* = .{
        .header = .{ .tag = .continuation },
        .registers = saved_regs,
        .frames = saved_frames,
        .frame_count = frame_count,
        .handlers = saved_handlers,
        .handler_count = handler_count,
        .wind_records = saved_winds,
        .wind_count = wind_count,
        .dst_reg = dst_reg,
        .dst_base = dst_base,
        .backing = backing,
    };
    self.finishAlloc(&cont.header, @sizeOf(Continuation) +
        registers.len * @sizeOf(Value) +
        frames.len * @sizeOf(SavedFrame) +
        handlers.len * @sizeOf(SavedHandler) +
        wind_records.len * @sizeOf(WindRecord));
    return types.makePointer(&cont.header);
}

/// Allocate an escape continuation (call/ec). Unlike a full continuation,
/// this copies nothing: it records only the stack depths to unwind back to.
/// Capture is therefore O(1) with a single allocation and no backing buffer.
pub fn allocEscapeContinuation(
    self: *GC,
    target_frame_count: usize,
    target_wind_count: usize,
    target_handler_count: usize,
    dst_reg: u16,
    dst_base: u32,
) !Value {
    try self.maybeCollect();
    const cont = try self.allocator.create(Continuation);
    cont.* = .{
        .header = .{ .tag = .continuation },
        // No snapshot: empty slices keep GC mark loops no-ops.
        .registers = &.{},
        .frames = &.{},
        .frame_count = 0,
        .handlers = &.{},
        .handler_count = 0,
        .wind_records = &.{},
        .wind_count = 0,
        .dst_reg = dst_reg,
        .dst_base = dst_base,
        .backing = &.{},
        .is_escape = true,
        .valid = true,
        .target_frame_count = target_frame_count,
        .target_wind_count = target_wind_count,
        .target_handler_count = target_handler_count,
    };
    self.finishAlloc(&cont.header, @sizeOf(Continuation));
    return types.makePointer(&cont.header);
}

pub fn allocComplex(self: *GC, real: f64, imag: f64) !Value {
    return self.allocComplexEx(real, imag, false, false);
}

pub fn allocComplexEx(self: *GC, real: f64, imag: f64, exact_real: bool, exact_imag: bool) !Value {
    try self.maybeCollect();
    const c = try self.allocator.create(types.Complex);
    c.* = .{
        .header = .{ .tag = .complex },
        .real = real,
        .imag = imag,
        .exact_real = exact_real,
        .exact_imag = exact_imag,
    };
    self.finishAlloc(&c.header, @sizeOf(types.Complex));
    return types.makePointer(&c.header);
}

pub fn allocParameter(self: *GC, init_value: Value, converter: Value) !Value {
    self.rootArgs2(init_value, converter);
    try self.maybeCollect();
    self.clearArgRoots();
    const p = try self.allocator.create(types.ParameterObject);
    p.* = .{
        .header = .{ .tag = .parameter },
        .value = init_value,
        .converter = converter,
    };
    self.finishAlloc(&p.header, @sizeOf(types.ParameterObject));
    return types.makePointer(&p.header);
}

pub fn allocFfiLibrary(self: *GC, handle: ?*anyopaque, name: []const u8) !Value {
    // Copy before collecting: `name` may alias a SchemeString's bytes.
    const owned_name = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(owned_name);
    try self.maybeCollect();
    const lib = try self.allocator.create(FfiLibrary);
    lib.* = .{
        .header = .{ .tag = .ffi_library },
        .handle = handle,
        .name = owned_name,
    };
    self.finishAlloc(&lib.header, @sizeOf(FfiLibrary) + name.len);
    return types.makePointer(&lib.header);
}

pub fn allocFfiFunction(self: *GC, symbol: *anyopaque, library: Value, name: []const u8, param_types: []const FfiType, return_type: FfiType) !Value {
    // Copy before collecting: `name` may alias a SchemeString's bytes.
    const owned_name = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(owned_name);
    const owned_params = try self.allocator.dupe(FfiType, param_types);
    errdefer self.allocator.free(owned_params);
    self.rootArgs1(library);
    try self.maybeCollect();
    self.clearArgRoots();
    const ffi_fn = try self.allocator.create(FfiFunction);
    ffi_fn.* = .{
        .header = .{ .tag = .ffi_function },
        .symbol = symbol,
        .library = library,
        .name = owned_name,
        .param_types = owned_params,
        .return_type = return_type,
        .param_count = @intCast(param_types.len),
    };
    self.finishAlloc(&ffi_fn.header, @sizeOf(FfiFunction) + name.len + param_types.len * @sizeOf(FfiType));
    return types.makePointer(&ffi_fn.header);
}

pub fn allocFfiCallback(self: *GC, closure: Value, slot_index: u8, fn_ptr: *anyopaque) !Value {
    self.rootArgs1(closure);
    try self.maybeCollect();
    self.clearArgRoots();
    const cb = try self.allocator.create(FfiCallback);
    cb.* = .{
        .header = .{ .tag = .ffi_callback },
        .closure = closure,
        .slot_index = slot_index,
        .fn_ptr = fn_ptr,
        .active = true,
    };
    self.finishAlloc(&cb.header, @sizeOf(FfiCallback));
    return types.makePointer(&cb.header);
}

pub fn allocRandomSource(self: *GC, seed: u64) !Value {
    try self.maybeCollect();
    const rs = try self.allocator.create(RandomSource);
    rs.* = .{
        .header = .{ .tag = .random_source },
        .prng = std.Random.DefaultPrng.init(seed),
    };
    self.finishAlloc(&rs.header, @sizeOf(RandomSource));
    return types.makePointer(&rs.header);
}

pub fn allocFiber(self: *GC, thunk: Value, id: u32) !*@import("fiber.zig").Fiber {
    self.rootArgs1(thunk);
    try self.maybeCollect();
    self.clearArgRoots();
    const fiber_mod = @import("fiber.zig");
    const registers = try allocSliceNoFill(self.allocator, Value, types.INITIAL_FIBER_REGISTER_CAPACITY);
    errdefer freeSliceNoFill(self.allocator, Value, registers);
    const frames = try allocSliceNoFill(self.allocator, types.CallFrame, types.INITIAL_FIBER_FRAME_CAPACITY);
    errdefer freeSliceNoFill(self.allocator, types.CallFrame, frames);
    const fiber = try self.allocator.create(fiber_mod.Fiber);
    fiber.* = .{
        .header = .{ .tag = .fiber },
        .registers = registers,
        .frames = frames,
        .frame_count = 0,
        .handler_stack = undefined,
        .handler_count = 0,
        .wind_stack = undefined,
        .wind_count = 0,
        .current_exception = null,
        .continuation_invoked = false,
        .continuation_value = types.VOID,
        .status = .created,
        .thunk = thunk,
        .result = types.VOID,
        .waiting_on = types.VOID,
        .id = id,
        .name = types.VOID,
        .specific = types.VOID,
        .deadline_ns = null,
        .timed_out = false,
        .terminated = false,
        .param_overrides = std.AutoHashMap(usize, Value).init(self.allocator),
    };
    @memset(fiber.registers, types.UNDEFINED);
    self.finishAlloc(&fiber.header, @sizeOf(fiber_mod.Fiber) +
        registers.len * @sizeOf(Value) +
        frames.len * @sizeOf(types.CallFrame));
    return fiber;
}

pub fn allocChannel(self: *GC) !Value {
    try self.maybeCollect();
    const ch = try self.allocator.create(types.Channel);
    ch.* = .{
        .header = .{ .tag = .channel },
        .head = types.NIL,
        .tail = types.NIL,
    };
    self.finishAlloc(&ch.header, @sizeOf(types.Channel));
    return types.makePointer(&ch.header);
}

/// KEP-0002 §6: a bounded channel, `(make-channel capacity)`. Separate
/// from allocChannel (rather than an optional parameter) so the
/// pre-Phase-4 call sites that construct an unbounded channel need no
/// changes.
pub fn allocChannelBounded(self: *GC, capacity: u32) !Value {
    try self.maybeCollect();
    const ch = try self.allocator.create(types.Channel);
    ch.* = .{
        .header = .{ .tag = .channel },
        .head = types.NIL,
        .tail = types.NIL,
        .capacity = capacity,
    };
    self.finishAlloc(&ch.header, @sizeOf(types.Channel));
    return types.makePointer(&ch.header);
}

/// A promoted-channel stub: a new counted reference to an existing
/// SharedChannel (KEP-0002 §2), allocated on this heap by deepCopy's
/// `.channel` alias arm. `shared` isn't a Value, so there's nothing to
/// root beyond the usual maybeCollect discipline.
pub fn allocChannelStub(self: *GC, shared: *anyopaque) !Value {
    try self.maybeCollect();
    const ch = try self.allocator.create(types.Channel);
    ch.* = .{
        .header = .{ .tag = .channel },
        .head = types.NIL,
        .tail = types.NIL,
        .shared = shared,
    };
    self.finishAlloc(&ch.header, @sizeOf(types.Channel));
    return types.makePointer(&ch.header);
}

pub fn allocMutex(self: *GC, name: Value) !Value {
    self.rootArgs1(name);
    try self.maybeCollect();
    self.clearArgRoots();
    const m = try self.allocator.create(types.Mutex);
    m.* = .{
        .header = .{ .tag = .mutex },
        .name = name,
        .owner = types.VOID,
        .locked = false,
        .abandoned = false,
        .specific = types.VOID,
    };
    self.finishAlloc(&m.header, @sizeOf(types.Mutex));
    return types.makePointer(&m.header);
}

pub fn allocConditionVariable(self: *GC, name: Value) !Value {
    self.rootArgs1(name);
    try self.maybeCollect();
    self.clearArgRoots();
    const cv = try self.allocator.create(types.ConditionVariable);
    cv.* = .{
        .header = .{ .tag = .condition_variable },
        .name = name,
        .specific = types.VOID,
    };
    self.finishAlloc(&cv.header, @sizeOf(types.ConditionVariable));
    return types.makePointer(&cv.header);
}

pub fn allocSrfi18Time(self: *GC, seconds: i64, nanoseconds: i64, time_type: types.TimeType) !Value {
    try self.maybeCollect();
    const t = try self.allocator.create(types.Srfi18Time);
    t.* = .{
        .header = .{ .tag = .srfi18_time },
        .seconds = seconds,
        .nanoseconds = nanoseconds,
        .time_type = time_type,
    };
    self.finishAlloc(&t.header, @sizeOf(types.Srfi18Time));
    return types.makePointer(&t.header);
}

pub fn allocHashTable(self: *GC, initial_capacity: usize) !Value {
    try self.maybeCollect();
    // Ensure capacity is a power of 2 (minimum 8)
    var cap = if (initial_capacity < 8) @as(usize, 8) else initial_capacity;
    if (cap & (cap - 1) != 0) {
        cap = @as(usize, 1) << @intCast(@as(std.math.Log2Int(usize), @intCast(@bitSizeOf(usize) - @clz(cap))));
    }
    const entries = try allocSliceNoFill(self.allocator, HashEntry, cap);
    errdefer freeSliceNoFill(self.allocator, HashEntry, entries);
    for (entries) |*e| {
        e.* = .{ .key = 0, .value = 0, .state = .empty };
    }
    const ht = try self.allocator.create(HashTable);
    ht.* = .{
        .header = .{ .tag = .hash_table },
        .entries = entries,
        .count = 0,
        .capacity = cap,
        .compare_mode = .equal,
        .equiv_fn = 0,
        .hash_fn = 0,
    };
    self.finishAlloc(&ht.header, @sizeOf(HashTable) + cap * @sizeOf(HashEntry));
    return types.makePointer(&ht.header);
}

pub fn allocBignumFromI64(self: *GC, n: i64) !Value {
    try self.maybeCollect();
    const limbs = try allocSliceNoFill(self.allocator, u64, 1);
    errdefer freeSliceNoFill(self.allocator, u64, limbs);
    const bn = try self.allocator.create(Bignum);
    const mag: u64 = if (n < 0) @intCast(-@as(i128, n)) else @intCast(n);
    limbs[0] = mag;
    bn.* = .{
        .header = .{ .tag = .bignum },
        .limbs = limbs,
        .len = if (mag == 0) 0 else 1,
        .positive = n >= 0,
    };
    self.finishAlloc(&bn.header, @sizeOf(Bignum) + @sizeOf(u64));
    return types.makePointer(&bn.header);
}

pub fn allocBignumFromLimbs(self: *GC, limbs: []const u64, len: usize, positive: bool) !Value {
    // Copy before collecting: `limbs` often aliases a source Bignum's limb
    // array (negate, abs, remainder). Collecting first frees that bignum
    // when the caller holds it only in a local, and the fresh `owned`
    // block can then land in the freed limbs' place — the "@memcpy
    // arguments alias" crash under -Dgc-stress=true (#1401).
    const owned = try dupeSliceNoFill(self.allocator, u64, limbs);
    errdefer freeSliceNoFill(self.allocator, u64, owned);
    try self.maybeCollect();
    const bn = try self.allocator.create(Bignum);
    bn.* = .{
        .header = .{ .tag = .bignum },
        .limbs = owned,
        .len = len,
        .positive = positive,
    };
    self.finishAlloc(&bn.header, @sizeOf(Bignum) + limbs.len * @sizeOf(u64));
    return types.makePointer(&bn.header);
}

pub fn allocRational(self: *GC, num: Value, den: Value) !Value {
    self.rootArgs2(num, den);
    try self.maybeCollect();
    self.clearArgRoots();
    const rat = try self.allocator.create(Rational);
    rat.* = .{
        .header = .{ .tag = .rational },
        .numerator = num,
        .denominator = den,
    };
    self.finishAlloc(&rat.header, @sizeOf(Rational));
    return types.makePointer(&rat.header);
}

pub fn allocFileInfo(self: *GC, info: struct {
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
    file_type: types.FileInfo.FileType,
}) !Value {
    try self.maybeCollect();
    const fi = try self.allocator.create(types.FileInfo);
    fi.* = .{
        .header = .{ .tag = .file_info },
        .size = info.size,
        .mtime = info.mtime,
        .atime = info.atime,
        .ctime = info.ctime,
        .dev = info.dev,
        .ino = info.ino,
        .nlinks = info.nlinks,
        .rdev = info.rdev,
        .blksize = info.blksize,
        .blocks = info.blocks,
        .mode = info.mode,
        .uid = info.uid,
        .gid = info.gid,
        .file_type = info.file_type,
    };
    self.finishAlloc(&fi.header, @sizeOf(types.FileInfo));
    return types.makePointer(&fi.header);
}

pub fn allocUserInfo(self: *GC, name: []const u8, uid: u32, gid: u32, home_dir: []const u8, shell: []const u8, full_name: []const u8) !Value {
    // Copy before collecting (see allocString).
    const name_copy = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(name_copy);
    const home_copy = try self.allocator.dupe(u8, home_dir);
    errdefer self.allocator.free(home_copy);
    const shell_copy = try self.allocator.dupe(u8, shell);
    errdefer self.allocator.free(shell_copy);
    const gecos_copy = try self.allocator.dupe(u8, full_name);
    errdefer self.allocator.free(gecos_copy);
    try self.maybeCollect();
    const ui = try self.allocator.create(types.UserInfo);
    ui.* = .{
        .header = .{ .tag = .user_info },
        .name = name_copy,
        .uid = uid,
        .gid = gid,
        .home_dir = home_copy,
        .shell = shell_copy,
        .full_name = gecos_copy,
    };
    self.finishAlloc(&ui.header, @sizeOf(types.UserInfo) + name.len + home_dir.len + shell.len + full_name.len);
    return types.makePointer(&ui.header);
}

pub fn allocGroupInfo(self: *GC, name: []const u8, gid: u32) !Value {
    // Copy before collecting (see allocString).
    const name_copy = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(name_copy);
    try self.maybeCollect();
    const gi = try self.allocator.create(types.GroupInfo);
    gi.* = .{
        .header = .{ .tag = .group_info },
        .name = name_copy,
        .gid = gid,
    };
    self.finishAlloc(&gi.header, @sizeOf(types.GroupInfo) + name.len);
    return types.makePointer(&gi.header);
}

pub fn allocEnvironment(self: *GC, env_map: *std.StringHashMap(Value), owned: bool, immutable: bool) !Value {
    try self.maybeCollect();
    const se = try self.allocator.create(types.SchemeEnvironment);
    se.* = .{
        .header = .{ .tag = .scheme_environment },
        .env = env_map,
        .owned = owned,
        .immutable = immutable,
    };
    self.finishAlloc(&se.header, @sizeOf(types.SchemeEnvironment));
    return types.makePointer(&se.header);
}

pub fn allocEphemeron(self: *GC, key: Value, value: Value) !Value {
    self.rootArgs2(key, value);
    try self.maybeCollect();
    self.clearArgRoots();
    const eph = try self.allocator.create(types.Ephemeron);
    eph.* = .{
        .header = .{ .tag = .ephemeron },
        .key = key,
        .value = value,
    };
    self.finishAlloc(&eph.header, @sizeOf(types.Ephemeron));
    return types.makePointer(&eph.header);
}

pub fn allocGuardian(self: *GC, is_transport: bool) !Value {
    try self.maybeCollect();
    const g = try self.allocator.create(types.Guardian);
    g.* = .{
        .header = .{ .tag = .guardian },
        .is_transport = is_transport,
    };
    self.finishAlloc(&g.header, @sizeOf(types.Guardian));
    return types.makePointer(&g.header);
}

pub fn allocTransportCell(self: *GC, key: Value, value: Value) !Value {
    self.rootArgs2(key, value);
    try self.maybeCollect();
    self.clearArgRoots();
    const tc = try self.allocator.create(types.TransportCell);
    tc.* = .{
        .header = .{ .tag = .transport_cell },
        .key = key,
        .value = value,
    };
    self.finishAlloc(&tc.header, @sizeOf(types.TransportCell));
    return types.makePointer(&tc.header);
}

pub fn allocDirectoryObject(self: *GC, dir: *anyopaque, include_dotfiles: bool) !Value {
    try self.maybeCollect();
    const d = try self.allocator.create(types.DirectoryObject);
    d.* = .{
        .header = .{ .tag = .directory_object },
        .dir = dir,
        .include_dotfiles = include_dotfiles,
    };
    self.finishAlloc(&d.header, @sizeOf(types.DirectoryObject));
    return types.makePointer(&d.header);
}

pub fn allocMultipleValues(self: *GC, values: []const Value) !Value {
    // Copy before collecting and root the values across the collection
    // (see allocVector).
    const owned = try dupeSliceNoFill(self.allocator, Value, values);
    errdefer freeSliceNoFill(self.allocator, Value, owned);
    const saved_slice_roots = self.slice_roots;
    self.slice_roots = owned;
    defer self.slice_roots = saved_slice_roots;
    try self.maybeCollect();
    const mv = try self.allocator.create(MultipleValues);
    mv.* = .{
        .header = .{ .tag = .multiple_values },
        .values = owned,
    };
    self.finishAlloc(&mv.header, @sizeOf(MultipleValues) + values.len * @sizeOf(Value));
    return types.makePointer(&mv.header);
}

// -- Convenience: build a proper list from a slice
pub fn makeList(self: *GC, items: []const Value) !Value {
    if (items.len == 0) return types.NIL;
    // Copy into raw memory first — `items` may alias a heap object's
    // storage (vector->list passes vec.data) that a collection can free —
    // then root the copy: each allocPair only arg-roots the item being
    // consed, so the not-yet-consed items would otherwise be collectable.
    const copy = try self.allocator.dupe(Value, items);
    defer self.allocator.free(copy);
    const saved_slice_roots = self.slice_roots;
    self.slice_roots = copy;
    defer self.slice_roots = saved_slice_roots;
    var result: Value = types.NIL;
    self.pushRoot(&result);
    defer self.popRoot();
    var i = copy.len;
    while (i > 0) {
        i -= 1;
        result = try self.allocPair(copy[i], result);
    }
    return result;
}
