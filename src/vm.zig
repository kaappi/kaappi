const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const Value = types.Value;
const OpCode = types.OpCode;

pub const VMError = error{
    StackOverflow,
    TypeError,
    ArityMismatch,
    UndefinedVariable,
    NotAProcedure,
    OutOfMemory,
    InvalidBytecode,
    DivisionByZero,
    CompileError,
};

const MAX_FRAMES = 256;
const MAX_REGISTERS = 1024;

const CallFrame = struct {
    closure: ?*types.Closure,
    native: ?*types.NativeFn = null,
    code: []const u8,
    ip: usize,
    base: u16,
    dst: u8,
};

pub const VM = struct {
    gc: *memory.GC,
    registers: [MAX_REGISTERS]Value = undefined,
    frames: [MAX_FRAMES]CallFrame = undefined,
    frame_count: usize = 0,
    globals: std.StringHashMap(Value),
    output: std.ArrayList(u8),

    pub fn init(gc: *memory.GC) VM {
        var vm = VM{
            .gc = gc,
            .globals = std.StringHashMap(Value).init(gc.allocator),
            .output = .empty,
        };
        @memset(&vm.registers, types.UNDEFINED);
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.globals.deinit();
        self.output.deinit(self.gc.allocator);
    }

    pub fn defineGlobal(self: *VM, name: []const u8, value: Value) !void {
        try self.globals.put(name, value);
    }

    pub fn execute(self: *VM, func: *types.Function) VMError!Value {
        // Create a top-level closure
        const closure_val = self.gc.allocClosure(func) catch return VMError.OutOfMemory;
        const closure = types.toObject(closure_val).as(types.Closure);

        // Push initial frame
        self.frames[0] = .{
            .closure = closure,
            .code = func.code.items,
            .ip = 0,
            .base = 0,
            .dst = 0,
        };
        self.frame_count = 1;

        return self.run();
    }

    fn run(self: *VM) VMError!Value {
        while (self.frame_count > 0) {
            const frame = &self.frames[self.frame_count - 1];
            if (frame.ip >= frame.code.len) return VMError.InvalidBytecode;

            const op: OpCode = @enumFromInt(frame.code[frame.ip]);
            frame.ip += 1;

            switch (op) {
                .load_const => {
                    const dst = self.readU8(frame);
                    const idx = self.readU16(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    self.registers[frame.base + dst] = closure.func.constants.items[idx];
                },
                .load_nil => {
                    const dst = self.readU8(frame);
                    self.registers[frame.base + dst] = types.NIL;
                },
                .load_true => {
                    const dst = self.readU8(frame);
                    self.registers[frame.base + dst] = types.TRUE;
                },
                .load_false => {
                    const dst = self.readU8(frame);
                    self.registers[frame.base + dst] = types.FALSE;
                },
                .load_void => {
                    const dst = self.readU8(frame);
                    self.registers[frame.base + dst] = types.VOID;
                },
                .move => {
                    const dst = self.readU8(frame);
                    const src = self.readU8(frame);
                    self.registers[frame.base + dst] = self.registers[frame.base + src];
                },
                .get_global => {
                    const dst = self.readU8(frame);
                    const sym_idx = self.readU16(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    const sym = closure.func.constants.items[sym_idx];
                    const name = types.symbolName(sym);
                    self.registers[frame.base + dst] = self.globals.get(name) orelse return VMError.UndefinedVariable;
                },
                .set_global => {
                    const sym_idx = self.readU16(frame);
                    const src = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    const sym = closure.func.constants.items[sym_idx];
                    const name = types.symbolName(sym);
                    self.globals.put(name, self.registers[frame.base + src]) catch return VMError.OutOfMemory;
                },
                .get_upvalue => {
                    const dst = self.readU8(frame);
                    const idx = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    self.registers[frame.base + dst] = closure.upvalues[idx];
                },
                .set_upvalue => {
                    const idx = self.readU8(frame);
                    const src = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    closure.upvalues[idx] = self.registers[frame.base + src];
                },
                .jump => {
                    const offset = self.readI16(frame);
                    const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                    frame.ip = @intCast(new_ip);
                },
                .jump_false => {
                    const test_reg = self.readU8(frame);
                    const offset = self.readI16(frame);
                    if (!types.isTruthy(self.registers[frame.base + test_reg])) {
                        const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                        frame.ip = @intCast(new_ip);
                    }
                },
                .jump_true => {
                    const test_reg = self.readU8(frame);
                    const offset = self.readI16(frame);
                    if (types.isTruthy(self.registers[frame.base + test_reg])) {
                        const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                        frame.ip = @intCast(new_ip);
                    }
                },
                .call => {
                    const base_reg = self.readU8(frame);
                    const nargs = self.readU8(frame);
                    const callee = self.registers[frame.base + base_reg];
                    try self.callValue(callee, frame.base + base_reg, nargs);
                },
                .tail_call => {
                    const base_reg = self.readU8(frame);
                    const nargs = self.readU8(frame);
                    const abs_base = frame.base + base_reg;
                    const callee = self.registers[abs_base];

                    if (types.isClosure(callee)) {
                        const closure = types.toObject(callee).as(types.Closure);
                        const func = closure.func;

                        if (!func.is_variadic) {
                            if (nargs != func.arity) return VMError.ArityMismatch;
                        } else {
                            if (nargs < func.arity) return VMError.ArityMismatch;
                            const rest_start = func.arity;
                            var rest_list: Value = types.NIL;
                            var ri: u8 = nargs;
                            while (ri > rest_start) {
                                ri -= 1;
                                rest_list = self.gc.allocPair(
                                    self.registers[abs_base + 1 + ri],
                                    rest_list,
                                ) catch return VMError.OutOfMemory;
                            }
                            self.registers[abs_base + 1 + rest_start] = rest_list;
                        }

                        // Move args down to current frame's parameter area
                        const arg_count = if (func.is_variadic) func.arity + 1 else nargs;
                        for (0..arg_count) |i| {
                            self.registers[frame.base + i] = self.registers[abs_base + 1 + i];
                        }

                        // Replace frame in-place — no frame_count change
                        frame.closure = closure;
                        frame.code = func.code.items;
                        frame.ip = 0;
                    } else if (types.isNativeFn(callee)) {
                        const native = types.toObject(callee).as(types.NativeFn);
                        switch (native.arity) {
                            .exact => |expected| {
                                if (nargs != expected) return VMError.ArityMismatch;
                            },
                            .variadic => |min| {
                                if (nargs < min) return VMError.ArityMismatch;
                            },
                        }
                        const args = self.registers[abs_base + 1 .. abs_base + 1 + nargs];
                        const result = native.func(args) catch |err| {
                            return switch (err) {
                                error.TypeError => VMError.TypeError,
                                error.DivisionByZero => VMError.DivisionByZero,
                                error.OutOfMemory => VMError.OutOfMemory,
                                else => VMError.InvalidBytecode,
                            };
                        };
                        const return_dst = frame.dst;
                        self.frame_count -= 1;
                        if (self.frame_count == 0) {
                            return result;
                        }
                        const caller = &self.frames[self.frame_count - 1];
                        self.registers[caller.base + return_dst] = result;
                    } else {
                        return VMError.NotAProcedure;
                    }
                },
                .@"return" => {
                    const src = self.readU8(frame);
                    const result = self.registers[frame.base + src];
                    const return_dst = frame.dst;
                    self.frame_count -= 1;
                    if (self.frame_count == 0) {
                        return result;
                    }
                    const caller = &self.frames[self.frame_count - 1];
                    self.registers[caller.base + return_dst] = result;
                },
                .closure => {
                    const dst = self.readU8(frame);
                    const idx = self.readU16(frame);
                    const parent_closure = frame.closure orelse return VMError.InvalidBytecode;
                    const func_val = parent_closure.func.constants.items[idx];
                    const func = types.toObject(func_val).as(types.Function);

                    const cls_val = self.gc.allocClosure(func) catch return VMError.OutOfMemory;
                    const cls = types.toObject(cls_val).as(types.Closure);

                    // Fill upvalues
                    for (cls.upvalues, 0..) |_, i| {
                        const is_local = frame.code[frame.ip] == 1;
                        frame.ip += 1;
                        const index = frame.code[frame.ip];
                        frame.ip += 1;

                        if (is_local) {
                            cls.upvalues[i] = self.registers[frame.base + index];
                        } else {
                            cls.upvalues[i] = parent_closure.upvalues[index];
                        }
                    }

                    self.registers[frame.base + dst] = cls_val;
                },
                .close_upvalue => {
                    _ = self.readU8(frame);
                    // TODO: implement upvalue closing
                },
                .cons => {
                    const dst = self.readU8(frame);
                    const car_reg = self.readU8(frame);
                    const cdr_reg = self.readU8(frame);
                    const pair = self.gc.allocPair(
                        self.registers[frame.base + car_reg],
                        self.registers[frame.base + cdr_reg],
                    ) catch return VMError.OutOfMemory;
                    self.registers[frame.base + dst] = pair;
                },
                .halt => {
                    return types.VOID;
                },
                else => return VMError.InvalidBytecode,
            }
        }
        return types.VOID;
    }

    fn callValue(self: *VM, callee: Value, base: u16, nargs: u8) VMError!void {
        if (types.isClosure(callee)) {
            const closure = types.toObject(callee).as(types.Closure);
            const func = closure.func;

            if (!func.is_variadic) {
                if (nargs != func.arity) return VMError.ArityMismatch;
            } else {
                if (nargs < func.arity) return VMError.ArityMismatch;
                // Collect rest args into a list
                const rest_start = func.arity;
                var rest_list: Value = types.NIL;
                var i: u8 = nargs;
                while (i > rest_start) {
                    i -= 1;
                    rest_list = self.gc.allocPair(
                        self.registers[base + 1 + i],
                        rest_list,
                    ) catch return VMError.OutOfMemory;
                }
                self.registers[base + 1 + rest_start] = rest_list;
            }

            if (self.frame_count >= MAX_FRAMES) return VMError.StackOverflow;

            // The callee is in base, args are in base+1..base+nargs
            // New frame's registers start at base (callee reg becomes r0 for the function)
            const new_base = base + 1; // skip the callee register
            self.frames[self.frame_count] = .{
                .closure = closure,
                .code = func.code.items,
                .ip = 0,
                .base = new_base,
                .dst = @intCast(base - self.frames[self.frame_count - 1].base),
            };
            self.frame_count += 1;
        } else if (types.isNativeFn(callee)) {
            const native = types.toObject(callee).as(types.NativeFn);
            switch (native.arity) {
                .exact => |expected| {
                    if (nargs != expected) return VMError.ArityMismatch;
                },
                .variadic => |min| {
                    if (nargs < min) return VMError.ArityMismatch;
                },
            }

            const args = self.registers[base + 1 .. base + 1 + nargs];
            const result = native.func(args) catch |err| {
                return switch (err) {
                    error.TypeError => VMError.TypeError,
                    error.DivisionByZero => VMError.DivisionByZero,
                    error.OutOfMemory => VMError.OutOfMemory,
                    else => VMError.InvalidBytecode,
                };
            };

            // Store result in the callee's register (base_reg from the call instruction).
            // The compiler emits `call base nargs` and expects the result back in base.
            self.registers[base] = result;
        } else {
            return VMError.NotAProcedure;
        }
    }

    fn readU8(self: *VM, frame: *CallFrame) u8 {
        _ = self;
        const val = frame.code[frame.ip];
        frame.ip += 1;
        return val;
    }

    fn readU16(self: *VM, frame: *CallFrame) u16 {
        _ = self;
        const hi: u16 = frame.code[frame.ip];
        const lo: u16 = frame.code[frame.ip + 1];
        frame.ip += 2;
        return (hi << 8) | lo;
    }

    fn readI16(self: *VM, frame: *CallFrame) i16 {
        return @bitCast(self.readU16(frame));
    }

    // -- High-level eval --

    pub fn eval(self: *VM, source: []const u8) VMError!Value {
        const reader_mod = @import("reader.zig");
        var reader = reader_mod.Reader.init(self.gc, source);
        defer reader.deinit();

        var last_result: Value = types.VOID;
        while (reader.hasMore()) {
            const expr = reader.readDatum() catch return VMError.CompileError;
            const func = compiler_mod.compileExpression(self.gc, expr) catch return VMError.CompileError;
            last_result = try self.execute(func);
        }
        return last_result;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const primitives_mod = @import("primitives.zig");

fn makeTestVM(gc: *memory.GC) !VM {
    var vm = VM.init(gc);
    try primitives_mod.registerAll(&vm);
    return vm;
}

test "eval integer literal" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("42");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "eval boolean" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("#t"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("#f"));
}

test "eval arithmetic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ 1 2)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "eval if true" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(if #t 1 2)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(result));
}

test "eval if false" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(if #f 1 2)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "eval define and reference" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define x 42)");
    const result = try vm.eval("x");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "eval lambda and call" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("((lambda (x) (+ x 1)) 41)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "eval define function and call" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define add1 (lambda (x) (+ x 1)))");
    const result = try vm.eval("(add1 10)");
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(result));
}

test "eval quote" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("'(1 2 3)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
}

test "eval set!" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define x 1)");
    _ = try vm.eval("(set! x 99)");
    const result = try vm.eval("x");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "eval begin" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define a 0)");
    _ = try vm.eval("(define b 0)");
    _ = try vm.eval("(begin (set! a 1) (set! b 2))");
    const result = try vm.eval("(+ a b)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "eval nested arithmetic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ (* 2 3) (- 10 4))");
    try std.testing.expectEqual(@as(i64, 12), types.toFixnum(result));
}

test "tail-recursive loop does not overflow" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (loop n) (if (= n 0) (quote done) (loop (- n 1))))");
    const result = try vm.eval("(loop 1000000)");
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("done", types.symbolName(result));
}

test "tail-recursive factorial with accumulator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc))))");
    const result = try vm.eval("(fact 10 1)");
    try std.testing.expectEqual(@as(i64, 3628800), types.toFixnum(result));
}

test "mutual tail recursion" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))");
    _ = try vm.eval("(define (my-odd? n) (if (= n 0) #f (my-even? (- n 1))))");
    const result = try vm.eval("(my-even? 10000)");
    try std.testing.expectEqual(types.TRUE, result);
}

test "non-tail recursion still works" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))");
    const result = try vm.eval("(fib 10)");
    try std.testing.expectEqual(@as(i64, 55), types.toFixnum(result));
}

test "tail call in begin" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (count n) (if (= n 0) 0 (begin (count (- n 1)))))");
    const result = try vm.eval("(count 100000)");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// Phase 3: Derived expression forms
// ---------------------------------------------------------------------------

test "eval and" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(and)"));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(and 1 2 3)")));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(and 1 #f 3)"));
}

test "eval or" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.FALSE, try vm.eval("(or)"));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(or 1 2)")));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(or #f #f 3)")));
}

test "eval when and unless" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.VOID, try vm.eval("(when #t 42)"));
    try std.testing.expectEqual(types.VOID, try vm.eval("(when #f 42)"));
    try std.testing.expectEqual(types.VOID, try vm.eval("(unless #f 42)"));
    try std.testing.expectEqual(types.VOID, try vm.eval("(unless #t 42)"));
}

test "eval cond" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(cond (#t 1))")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(cond (#f 1) (else 2))")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(cond (#f 1) (#t 2) (else 3))")));
}

test "eval let" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(let ((x 1) (y 2)) (+ x y))")));
}

test "eval let*" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(let* ((x 1) (y (+ x 1))) y)")));
}

test "eval letrec" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(letrec ((f (lambda (n) (if (= n 0) 1 (* n (f (- n 1))))))) (f 5))");
    try std.testing.expectEqual(@as(i64, 120), types.toFixnum(result));
}

test "eval named let" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let loop ((i 0) (s 0)) (if (= i 5) s (loop (+ i 1) (+ s i))))");
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(result));
}

test "eval do" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Simple do: just counting - void result
    const r0 = try vm.eval("(do ((i 0 (+ i 1))) ((= i 3)))");
    try std.testing.expectEqual(types.VOID, r0);

    // Simple do: just counting
    const r1 = try vm.eval("(do ((i 0 (+ i 1))) ((= i 3) i))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(r1));

    // Two variables with accumulation
    const result = try vm.eval("(do ((i 0 (+ i 1)) (s 0 (+ s i))) ((= i 5) s))");
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(result));
}
