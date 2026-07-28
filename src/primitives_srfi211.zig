//! SRFI-211 — Scheme Macro Libraries: procedural transformer constructors.
//!
//! `er-macro-transformer` and `lisp-transformer` wrap a Scheme procedure in
//! a procedural Transformer object (types.TransformerKind). Two paths use
//! them:
//!
//!   * A transformer-spec position — `(define-syntax foo
//!     (er-macro-transformer <expr>))` — is recognized STRUCTURALLY by
//!     resolveTransformerSpecRec (compiler_macro.zig), which evaluates
//!     `<expr>` at macro-definition time and never calls these primitives.
//!     That recognition is ambient (like `syntax-rules` itself), so these
//!     registrations exist for the other path and for hygiene: a
//!     syntax-rules template that emits one of these forms keeps the head
//!     unrenamed only because renameForHygiene preserves names bound to
//!     global procedures.
//!
//!   * A runtime call — `(define t (er-macro-transformer proc))` — yields a
//!     real Transformer value; `(define-syntax foo t)` then resolves it via
//!     resolveTransformerSpecRec's globals fallback. A Transformer is not
//!     itself callable, matching R6RS's "a transformer is not a procedure".
//!
//! Registered under the `(srfi 211 primitives)` registry library (the
//! public sub-libraries are portable `.sld` files re-exporting these; the
//! `*.primitives` naming avoids the registry-shadows-a-same-named-.sld
//! problem, same as srfi_237_primitives).

const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

const SRFI211 = LS.initOne(.srfi_211_primitives);

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "er-macro-transformer", .func = &erMacroTransformerFn, .arity = .{ .exact = 1 }, .libs = SRFI211 },
    .{ .name = "lisp-transformer", .func = &lispTransformerFn, .arity = .{ .exact = 1 }, .libs = SRFI211 },
};

fn makeProceduralTransformer(name: []const u8, kind: types.TransformerKind, args: []const Value) PrimitiveError!Value {
    if (!types.isProcedure(args[0])) return primitives.typeError(name, "procedure", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocProceduralTransformer(kind, args[0]) catch PrimitiveError.OutOfMemory;
}

fn erMacroTransformerFn(args: []const Value) PrimitiveError!Value {
    return makeProceduralTransformer("er-macro-transformer", .er_macro, args);
}

fn lispTransformerFn(args: []const Value) PrimitiveError!Value {
    return makeProceduralTransformer("lisp-transformer", .lisp_macro, args);
}
