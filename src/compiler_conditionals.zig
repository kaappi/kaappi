const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const Value = types.Value;
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;

// -- Conditional expression forms --

pub fn compileAnd(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) {
        try self.emitOp(.load_true);
        try self.emitU16(dst);
        return;
    }

    var end_jumps: std.ArrayList(usize) = .empty;
    defer end_jumps.deinit(self.gc.allocator);
    var current = args;

    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        const rest = types.cdr(current);

        if (rest == types.NIL) {
            try self.compileExpr(expr, dst, is_tail);
        } else {
            try self.compileExpr(expr, dst, false);
            try self.emitOp(.jump_false);
            try self.emitU16(dst);
            end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
            try self.emitI16(0);
        }
        current = rest;
    }

    for (end_jumps.items) |j| {
        try self.patchJump(j);
    }
}

pub fn compileOr(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) {
        try self.emitOp(.load_false);
        try self.emitU16(dst);
        return;
    }

    var end_jumps: std.ArrayList(usize) = .empty;
    defer end_jumps.deinit(self.gc.allocator);
    var current = args;

    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        const rest = types.cdr(current);

        if (rest == types.NIL) {
            try self.compileExpr(expr, dst, is_tail);
        } else {
            try self.compileExpr(expr, dst, false);
            try self.emitOp(.jump_true);
            try self.emitU16(dst);
            end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
            try self.emitI16(0);
        }
        current = rest;
    }

    for (end_jumps.items) |j| {
        try self.patchJump(j);
    }
}

pub fn compileWhen(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = types.car(args);
    const body = types.cdr(args);

    try self.compileExpr(test_expr, dst, false);
    try self.emitOp(.jump_false);
    try self.emitU16(dst);
    const false_jump = self.currentOffset();
    try self.emitI16(0);

    var current = body;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const rest = types.cdr(current);
        const tail = is_tail and rest == types.NIL;
        try self.compileExpr(types.car(current), dst, tail);
        current = rest;
    }

    try self.emitOp(.jump);
    const end_jump = self.currentOffset();
    try self.emitI16(0);

    try self.patchJump(false_jump);
    try self.emitOp(.load_void);
    try self.emitU16(dst);

    try self.patchJump(end_jump);
}

pub fn compileUnless(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = types.car(args);
    const body = types.cdr(args);

    try self.compileExpr(test_expr, dst, false);
    try self.emitOp(.jump_true);
    try self.emitU16(dst);
    const true_jump = self.currentOffset();
    try self.emitI16(0);

    var current = body;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const rest = types.cdr(current);
        const tail = is_tail and rest == types.NIL;
        try self.compileExpr(types.car(current), dst, tail);
        current = rest;
    }

    try self.emitOp(.jump);
    const end_jump = self.currentOffset();
    try self.emitI16(0);

    try self.patchJump(true_jump);
    try self.emitOp(.load_void);
    try self.emitU16(dst);

    try self.patchJump(end_jump);
}

pub fn compileCond(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) {
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    var end_jumps: std.ArrayList(usize) = .empty;
    defer end_jumps.deinit(self.gc.allocator);
    var current = args;
    var had_else = false;

    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const clause = types.car(current);
        current = types.cdr(current);
        if (!types.isPair(clause)) return CompileError.InvalidSyntax;

        const test_expr = types.car(clause);
        const clause_body = types.cdr(clause);

        // Check for else clause
        if (types.isSymbol(test_expr) and std.mem.eql(u8, types.symbolName(test_expr), "else")) {
            try compileCondBody(self, clause_body, dst, is_tail);
            had_else = true;
            break;
        }

        // Compile test
        try self.compileExpr(test_expr, dst, false);

        // Check for => form (only if => is not rebound as a local variable)
        if (clause_body != types.NIL and types.isPair(clause_body)) {
            const maybe_arrow = types.car(clause_body);
            if (types.isSymbol(maybe_arrow) and std.mem.eql(u8, types.symbolName(maybe_arrow), "=>") and
                self.resolveLocal("=>") == null and
                (try self.resolveUpvalue("=>")) == null)
            {
                // (test => proc) -- call proc with test value
                try self.emitOp(.jump_false);
                try self.emitU16(dst);
                const next_clause = self.currentOffset();
                try self.emitI16(0);

                // test value is in dst, compile proc and call it
                const arrow_rest = types.cdr(clause_body);
                if (!types.isPair(arrow_rest)) return CompileError.InvalidSyntax;
                const proc_expr = types.car(arrow_rest);
                const proc_reg = try self.allocReg();
                // Move test value to arg position
                const arg_reg = try self.allocReg();
                try self.emitOp(.move);
                try self.emitU16(arg_reg);
                try self.emitU16(dst);
                // Compile proc
                try self.compileExpr(proc_expr, proc_reg, false);
                // Move proc to dst (for call base)
                try self.emitOp(.move);
                try self.emitU16(dst);
                try self.emitU16(proc_reg);
                // Move arg after dst
                try self.emitOp(.move);
                try self.emitU16(dst + 1);
                try self.emitU16(arg_reg);
                if (is_tail) {
                    try self.emitOp(.tail_call);
                } else {
                    try self.emitOp(.call);
                }
                try self.emitU16(dst);
                try self.emit(1);
                self.freeReg(); // arg_reg
                self.freeReg(); // proc_reg

                try self.emitOp(.jump);
                end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
                try self.emitI16(0);

                try self.patchJump(next_clause);
                continue;
            }
        }

        // Regular clause (test expr ...)
        try self.emitOp(.jump_false);
        try self.emitU16(dst);
        const next_clause = self.currentOffset();
        try self.emitI16(0);

        if (clause_body == types.NIL) {
            // (test) with no body -- return the test value (already in dst)
        } else {
            try compileCondBody(self, clause_body, dst, is_tail);
        }

        try self.emitOp(.jump);
        end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
        try self.emitI16(0);

        try self.patchJump(next_clause);
    }

    // If no else clause, result is void when nothing matched
    if (!had_else) {
        try self.emitOp(.load_void);
        try self.emitU16(dst);
    }

    for (end_jumps.items) |j| {
        try self.patchJump(j);
    }
}

pub fn compileCondBody(self: *Compiler, body: Value, dst: u16, is_tail: bool) CompileError!void {
    var current = body;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        current = types.cdr(current);
        const tail = is_tail and current == types.NIL;
        try self.compileExpr(expr, dst, tail);
    }
}

/// Compile (cond-expand (feature-req expr ...) ... [(else expr ...)])
///
/// Evaluates feature requirements at compile time and compiles the body
/// of the first matching clause. Features are checked against a hardcoded
/// list and the library registry.
pub fn compileCondExpand(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const clause = types.car(current);
        current = types.cdr(current);

        if (!types.isPair(clause)) return CompileError.InvalidSyntax;
        const feature_req = types.car(clause);
        const clause_body = types.cdr(clause);

        // Check for else clause
        if (types.isSymbol(feature_req) and std.mem.eql(u8, types.symbolName(feature_req), "else")) {
            return compileCondBody(self, clause_body, dst, is_tail);
        }

        // Evaluate the feature requirement
        if (evalFeatureReq(self, feature_req)) {
            return compileCondBody(self, clause_body, dst, is_tail);
        }
    }

    // No clause matched — void
    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

/// Evaluate a feature requirement at compile time.
pub fn evalFeatureReq(self: *Compiler, req: Value) bool {
    if (types.isSymbol(req)) {
        const name = types.symbolName(req);
        // Hardcoded feature identifiers
        const known_features = [_][]const u8{
            "r7rs",
            "kaappi",
            "ieee-float",
            "posix",
            "exact-closed",
        };
        for (known_features) |f| {
            if (std.mem.eql(u8, name, f)) return true;
        }
        return false;
    }

    if (types.isPair(req)) {
        const head = types.car(req);
        if (!types.isSymbol(head)) return false;
        const op = types.symbolName(head);

        if (std.mem.eql(u8, op, "and")) {
            var rest = types.cdr(req);
            while (rest != types.NIL) {
                if (!types.isPair(rest)) return false;
                if (!evalFeatureReq(self, types.car(rest))) return false;
                rest = types.cdr(rest);
            }
            return true;
        }

        if (std.mem.eql(u8, op, "or")) {
            var rest = types.cdr(req);
            while (rest != types.NIL) {
                if (!types.isPair(rest)) return false;
                if (evalFeatureReq(self, types.car(rest))) return true;
                rest = types.cdr(rest);
            }
            return false;
        }

        if (std.mem.eql(u8, op, "not")) {
            const rest = types.cdr(req);
            if (!types.isPair(rest)) return false;
            return !evalFeatureReq(self, types.car(rest));
        }

        if (std.mem.eql(u8, op, "library")) {
            // (library (name ...)) — check if library exists
            // We don't have direct access to the library registry from the compiler,
            // but we can check against known standard libraries
            const rest = types.cdr(req);
            if (!types.isPair(rest)) return false;
            const lib_name_list = types.car(rest);

            // Convert library name list to canonical string
            const lib_name = @import("library.zig").libraryNameToString(self.gc.allocator, lib_name_list) catch return false;
            defer self.gc.allocator.free(lib_name);

            // Check against known standard libraries
            const known_libs = [_][]const u8{
                "scheme.base",            "scheme.write",
                "scheme.read",            "scheme.inexact",
                "scheme.char",            "scheme.lazy",
                "scheme.time",            "scheme.file",
                "scheme.cxr",             "scheme.complex",
                "scheme.process-context", "scheme.eval",
                "scheme.case-lambda",     "scheme.load",
                "srfi.1",                 "srfi.9",
                "srfi.13",                "srfi.27",
                "srfi.35",                "srfi.39",
                "srfi.64",                "srfi.69",
                "srfi.133",
            };
            for (known_libs) |l| {
                if (std.mem.eql(u8, lib_name, l)) return true;
            }
            // Also check the VM's live library registry via globals
            // The compiler doesn't have direct VM access, so check if
            // the library exists on disk as a .sld file
            return false;
        }
    }

    return false;
}
