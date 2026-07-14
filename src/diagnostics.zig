//! Diagnostic registry — the single source of truth for Kaappi's user-facing
//! diagnostic codes (KEP-0005, kaappi#1504).
//!
//! Every diagnostic Kaappi prints carries a stable `KP`-prefixed code so that
//! tools — AI agents, CI gates, editors — can match on an identifier instead of
//! scraping prose that is free to be reworded. The leading digit encodes the
//! pipeline stage the diagnostic came from:
//!
//!   KP1xxx  read / lexical      (reader.zig, reader_tokens.zig, reader_datum.zig)
//!   KP2xxx  expand / compile    (expander.zig, compiler*.zig, ir.zig)
//!   KP3xxx  runtime             (vm*.zig, primitives*.zig)
//!   KP4xxx  static analysis     (`kaappi check`, reserved — kaappi#1511)
//!   KP9xxx  internal / resource (internal-compiler-error and out-of-memory paths)
//!
//! Stability policy (KEP-0005 §5): once a code ships in a released version it is
//! NEVER renumbered and NEVER reused for a different meaning. A retired code is
//! reserved forever (a tombstone entry). Message text and explanations may be
//! reworded freely — that is the whole point of separating the stable code from
//! the mutable prose. See docs/dev/diagnostics.md.
//!
//! This registry is the keystone of the "machine legibility" campaign
//! (kaappi#1503): `--diagnostics=json`, `kaappi explain`, and `error-object-code`
//! all hang off it in later phases. Phase 1 (this file) gives every read /
//! expand / compile / runtime error a code in text output and retires the raw
//! `error.XxxYyy` Zig-enum leaks.

const std = @import("std");

pub const Severity = enum {
    /// Halts execution; the process exits non-zero.
    err,
    /// Advisory; does not by itself stop the program. Reserved for KP4xxx lint.
    warning,

    /// Lower-case label used by `kaappi explain` and its JSON form.
    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .err => "error",
            .warning => "warning",
        };
    }
};

/// The pipeline stage a code belongs to, recovered from its leading digit. The
/// taxonomy is documented in docs/dev/diagnostics.md; `kaappi explain` surfaces
/// the label so an agent can see which stage failed without re-deriving it.
pub const Stage = enum {
    read,
    compile,
    runtime,
    static_analysis,
    internal,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .read => "read",
            .compile => "compile",
            .runtime => "runtime",
            .static_analysis => "static-analysis",
            .internal => "internal",
        };
    }
};

/// A stable diagnostic code. The integer value IS the KP number, so
/// `undefined_variable` (= 3001) renders as "KP3001". Ordinals are a permanent
/// contract: never change or reuse an existing value once released (KEP-0005 §5).
/// New codes take the next free ordinal in their stage range.
pub const Code = enum(u16) {
    // -- KP1xxx — Read / lexical --------------------------------------------
    unexpected_eof = 1001,
    unexpected_char = 1002,
    unexpected_right_paren = 1003,
    invalid_number = 1004,
    invalid_character_name = 1005,
    unterminated_string = 1006,
    invalid_escape = 1007,
    dot_outside_list = 1008,
    nesting_too_deep = 1009,
    token_too_long = 1010,

    // -- KP2xxx — Expand / compile ------------------------------------------
    invalid_syntax = 2001,
    syntax_error = 2002,
    macro_expansion_limit = 2003,

    // -- KP3xxx — Runtime ---------------------------------------------------
    uncaught_exception = 3000,
    undefined_variable = 3001,
    type_error = 3002,
    arity_mismatch = 3003,
    division_by_zero = 3004,
    not_a_procedure = 3005,
    index_out_of_bounds = 3006,
    invalid_argument = 3007,
    stack_overflow = 3008,
    execution_timeout = 3009,

    // -- KP9xxx — Internal / resource exhaustion ----------------------------
    uncategorized = 9000,
    internal_error = 9001,
    out_of_memory = 9002,

    /// Width of a rendered code, e.g. "KP3001" — always "KP" + 4 digits.
    pub const render_width = 6;

    /// Render this code as "KPnnnn" into `buf`. Returns the written slice.
    pub fn render(self: Code, buf: *[render_width]u8) []const u8 {
        return std.fmt.bufPrint(buf, "KP{d:0>4}", .{@intFromEnum(self)}) catch unreachable;
    }

    /// The registry entry for this code.
    pub fn info(self: Code) Diagnostic {
        return lookup(self);
    }

    /// The pipeline stage this code came from, from its leading digit.
    pub fn stage(self: Code) Stage {
        return switch (@intFromEnum(self) / 1000) {
            1 => .read,
            2 => .compile,
            3 => .runtime,
            4 => .static_analysis,
            else => .internal, // 9xxx
        };
    }

    /// Resolve a user-supplied identifier to a registered code, for
    /// `kaappi explain <code>`. Accepts the rendered code case-insensitively
    /// with or without the "KP" prefix ("KP3001", "kp3001", "3001") as well as
    /// the stable kebab-case name ("undefined-variable"). Returns null when
    /// nothing matches so the caller can report an unknown-code usage error.
    pub fn fromString(s: []const u8) ?Code {
        if (s.len == 0) return null;

        // Numeric form, with an optional "KP"/"kp" prefix.
        var digits = s;
        if (digits.len >= 2 and (digits[0] == 'K' or digits[0] == 'k') and
            (digits[1] == 'P' or digits[1] == 'p'))
        {
            digits = digits[2..];
        }
        if (digits.len > 0 and isAllDigits(digits)) {
            const n = std.fmt.parseInt(u16, digits, 10) catch return null;
            inline for (std.enums.values(Code)) |c| {
                if (@intFromEnum(c) == n) return c;
            }
            return null;
        }

        // Name form: match the kebab-case name case-insensitively.
        for (table) |d| {
            if (std.ascii.eqlIgnoreCase(d.name, s)) return d.code;
        }
        return null;
    }

    /// The human-readable message template. In Phase 1 (kaappi#1504) most
    /// templates are complete sentences with no placeholders; a richer message
    /// supplied at the raise site (the VM/compiler "detail" buffers) overrides
    /// this when present. The template is the fallback that replaces the old
    /// raw-Zig-error-name output.
    pub fn message(self: Code) []const u8 {
        return lookup(self).template;
    }
};

pub const Diagnostic = struct {
    code: Code,
    /// Kebab-case short name, e.g. "undefined-variable". Stable alongside the code.
    name: []const u8,
    /// Human-readable message / template (see `Code.message`).
    template: []const u8,
    /// Prose explanation surfaced by `kaappi explain <code>` (kaappi#1507).
    /// Must be non-empty for every entry — enforced at compile time below.
    explanation: []const u8,
    /// A minimal snippet that triggers this diagnostic, shown by
    /// `kaappi explain <code>`. Where a genuine trigger cannot be an inline
    /// one-liner (deeply nested input, an internal invariant) the snippet is
    /// representative and says so. Must be non-empty — enforced at compile time.
    example: []const u8,
    severity: Severity = .err,
};

/// The registry. One entry per `Code`; completeness and uniqueness are enforced
/// by the `comptime` block at the bottom of this file, so this array is the
/// single source of truth an agent, the docs generator, and `kaappi explain`
/// all read from.
pub const table = [_]Diagnostic{
    // -- KP1xxx — Read / lexical --------------------------------------------
    .{
        .code = .unexpected_eof,
        .name = "unexpected-eof",
        .template = "unexpected end of input",
        .explanation =
        \\The reader reached the end of the input while a datum was still open —
        \\most often an unclosed '(' or an unterminated string or block comment.
        \\Check that every '(' has a matching ')' and every '"' is closed.
        ,
        .example = "(+ 1 2",
    },
    .{
        .code = .unexpected_char,
        .name = "unexpected-char",
        .template = "unexpected character",
        .explanation =
        \\The reader encountered a character that cannot begin or continue a datum
        \\at this position. A common cause is a malformed '#'-syntax such as an
        \\unknown '#\name' character literal or a stray '#'.
        ,
        .example = "#z",
    },
    .{
        .code = .unexpected_right_paren,
        .name = "unexpected-right-paren",
        .template = "unexpected ')'",
        .explanation =
        \\A ')' appeared with no matching '(' still open. Usually there is one
        \\closing parenthesis too many, or an earlier '(' was already closed.
        ,
        .example = "(cons 1 2))",
    },
    .{
        .code = .invalid_number,
        .name = "invalid-number",
        .template = "invalid number literal",
        .explanation =
        \\A token that looked like a number could not be parsed as one — for
        \\example a malformed radix prefix (#x, #o, #b, #e, #i), a bad exponent,
        \\or a rational with a zero denominator.
        ,
        .example = "1/0",
    },
    .{
        .code = .invalid_character_name,
        .name = "invalid-character-name",
        .template = "invalid character name",
        .explanation =
        \\A '#\...' character literal named something the reader does not know.
        \\Valid forms are a single character (#\a), a named character
        \\(#\newline, #\space, #\tab, ...), or a hex escape (#\x41).
        ,
        .example = "#\\foo",
    },
    .{
        .code = .unterminated_string,
        .name = "unterminated-string",
        .template = "unterminated string literal",
        .explanation =
        \\A string opened with '"' was never closed before end of input. Add the
        \\closing '"', or escape any literal '"' inside the string as '\"'.
        ,
        .example = "(display \"abc",
    },
    .{
        .code = .invalid_escape,
        .name = "invalid-escape",
        .template = "invalid escape sequence",
        .explanation =
        \\A '\' inside a string was followed by a character that is not a valid
        \\escape. R7RS allows \a \b \t \n \r \" \\ \x<hex>; and a line-continuation
        \\'\' followed by whitespace and a newline.
        ,
        .example = "(display \"\\q\")",
    },
    .{
        .code = .dot_outside_list,
        .name = "dot-outside-list",
        .template = "'.' outside of a list",
        .explanation =
        \\A '.' (dotted-pair marker) appeared where it is not allowed. It is legal
        \\only before the final element inside a list, as in (a . b) or (a b . c).
        ,
        .example = "(. 5)",
    },
    .{
        .code = .nesting_too_deep,
        .name = "nesting-too-deep",
        .template = "nesting too deep",
        .explanation =
        \\The datum nests more deeply than the reader's fixed limit. This usually
        \\means unbalanced parentheses producing runaway nesting rather than a
        \\genuinely deep literal.
        ,
        // Representative: a real trigger needs more open parens than the
        // reader's depth limit, too many to print inline.
        .example = "((((( ...nested past the reader's depth limit... )))))",
    },
    .{
        .code = .token_too_long,
        .name = "token-too-long",
        .template = "token too long",
        .explanation =
        \\A single token (identifier, number, or string) exceeded the reader's
        \\maximum token length. Split the input or shorten the token.
        ,
        // Representative: a real trigger is one token longer than the reader's
        // limit, too long to print inline.
        .example = "aaaaaaaa...  ; a single token longer than the reader's limit",
    },

    // -- KP2xxx — Expand / compile ------------------------------------------
    .{
        .code = .invalid_syntax,
        .name = "invalid-syntax",
        .template = "invalid syntax",
        .explanation =
        \\A special form was written incorrectly — for example an 'if' with no
        \\test, a 'define' with no body, or a 'lambda' whose parameter list is not
        \\a proper list of identifiers. Check the form against its expected shape.
        ,
        .example = "(if)",
    },
    .{
        .code = .syntax_error,
        .name = "syntax-error",
        .template = "syntax error",
        .explanation =
        \\A macro rejected its use, either via the R7RS 'syntax-error' keyword or
        \\because no 'syntax-rules' pattern matched the form. The accompanying
        \\message describes what the macro expected.
        ,
        .example = "(syntax-error \"must be a pair\" 1)",
    },
    .{
        .code = .macro_expansion_limit,
        .name = "macro-expansion-limit",
        .template = "macro expansion limit exceeded",
        .explanation =
        \\Macro expansion did not terminate within the implementation's step
        \\limit, which almost always indicates a macro that expands into itself
        \\without a base case.
        ,
        .example =
        \\(define-syntax loop (syntax-rules () ((_ x) (loop x))))
        \\(loop 1)
        ,
    },

    // -- KP3xxx — Runtime ---------------------------------------------------
    .{
        .code = .uncaught_exception,
        .name = "uncaught-exception",
        .template = "uncaught exception",
        .explanation =
        \\An object was raised (via 'raise', 'error', 'assert', or a library) and
        \\reached the top level without being caught. Wrap the code in 'guard' or
        \\'with-exception-handler' to handle it. The message shown is the payload
        \\of the raised object.
        ,
        .example = "(raise 'boom)",
    },
    .{
        .code = .undefined_variable,
        .name = "undefined-variable",
        .template = "undefined variable",
        .explanation =
        \\A variable was referenced that has no binding in scope. Check for a typo
        \\(Kaappi suggests the nearest defined name), a missing 'import', or a
        \\'define' that has not run yet because it appears after the reference.
        ,
        .example = "(display undefined-name)",
    },
    .{
        .code = .type_error,
        .name = "type-error",
        .template = "type error",
        .explanation =
        \\A procedure was applied to an argument of the wrong type — for example
        \\'car' on a non-pair or '+' on a non-number. The message names the
        \\procedure, the type it expected, and the value it got.
        ,
        .example = "(car 5)",
    },
    .{
        .code = .arity_mismatch,
        .name = "arity-mismatch",
        .template = "wrong number of arguments",
        .explanation =
        \\A procedure was called with a number of arguments its parameter list
        \\cannot accept. The message shows how many arguments were expected versus
        \\how many were supplied.
        ,
        .example = "(cons 1)",
    },
    .{
        .code = .division_by_zero,
        .name = "division-by-zero",
        .template = "division by zero",
        .explanation =
        \\An exact division, 'modulo', 'remainder', or 'quotient' had a zero
        \\divisor. Guard the divisor, or use inexact arithmetic where the result
        \\is a floating-point infinity or NaN instead of an error.
        ,
        .example = "(/ 1 0)",
    },
    .{
        .code = .not_a_procedure,
        .name = "not-a-procedure",
        .template = "attempt to call a non-procedure",
        .explanation =
        \\The operator position of a call evaluated to something that is not a
        \\procedure, as in (5 6). Check for an extra pair of parentheses or a name
        \\that is bound to a value rather than a procedure.
        ,
        .example = "(5 6)",
    },
    .{
        .code = .index_out_of_bounds,
        .name = "index-out-of-bounds",
        .template = "index out of bounds",
        .explanation =
        \\An index passed to a sequence operation (vector-ref, string-ref,
        \\list-ref, bytevector-u8-ref, ...) was negative or not less than the
        \\length of the sequence.
        ,
        .example = "(vector-ref (vector 1 2) 5)",
    },
    .{
        .code = .invalid_argument,
        .name = "invalid-argument",
        .template = "invalid argument",
        .explanation =
        \\An argument was of an acceptable type but outside the range or shape the
        \\procedure allows — for example a start index greater than an end index,
        \\or a value a procedure explicitly rejects.
        ,
        .example =
        \\(import (srfi 13))
        \\(string-join '() "," 'strict-infix)
        ,
    },
    .{
        .code = .stack_overflow,
        .name = "stack-overflow",
        .template = "stack overflow",
        .explanation =
        \\The call stack grew past its limit, almost always from unbounded
        \\non-tail recursion. Rewrite the recursion to be in tail position, or use
        \\an explicit accumulator or loop.
        ,
        .example =
        \\(define (sum n) (+ n (sum (+ n 1))))
        \\(sum 0)
        ,
    },
    .{
        .code = .execution_timeout,
        .name = "execution-timeout",
        .template = "execution timed out",
        .explanation =
        \\Execution exceeded a configured time budget and was interrupted. This is
        \\a sandbox / watchdog limit, not a fault in the program's logic per se.
        ,
        // Surfaces only under a time budget: kaappi --timeout 500 prog.scm
        .example = "(let loop () (loop))   ; run with --timeout 500",
    },

    // -- KP9xxx — Internal / resource exhaustion ----------------------------
    .{
        .code = .uncategorized,
        .name = "uncategorized",
        .template = "error",
        .explanation =
        \\A diagnostic that has not yet been assigned a specific code. Seeing this
        \\code is itself a gap worth reporting: the underlying condition should get
        \\its own registry entry.
        ,
        // No dedicated trigger — this is the fallback for a condition that has
        // not yet been given its own code.
        .example = "(no specific trigger — a catch-all for uncoded conditions)",
    },
    .{
        .code = .internal_error,
        .name = "internal-error",
        .template = "internal compiler error",
        .explanation =
        \\Kaappi hit a condition that should not be reachable — a corrupt bytecode
        \\stream or an internal limit. This indicates a bug in Kaappi itself;
        \\please report it with the program that triggered it.
        ,
        // No user-reachable trigger by design — correct input never produces
        // this; it signals a bug in Kaappi.
        .example = "(no trigger from correct input — signals a bug in Kaappi)",
    },
    .{
        .code = .out_of_memory,
        .name = "out-of-memory",
        .template = "out of memory",
        .explanation =
        \\Memory allocation failed. The program (or a single datum, program text,
        \\or data structure within it) is too large for the available heap.
        ,
        .example = "(make-bytevector 100000000000000)",
    },
};

/// Look up the registry entry for a code. Completeness is guaranteed at compile
/// time, so this never fails for a valid `Code`.
pub fn lookup(code: Code) Diagnostic {
    inline for (table) |d| {
        if (d.code == code) return d;
    }
    unreachable;
}

fn isAllDigits(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

// -- Internal bridge: Zig error set -> curated code -------------------------
//
// These map the implementation's internal error enums (ReadError, CompileError,
// ExpandError, the VM's KaappiError) onto curated registry codes. They are an
// implementation detail, NOT a public "the enum IS the code" contract: the code
// space is deliberately separate and curated (KEP-0005 "Alternatives
// considered"), so a coarse Zig error such as TypeError can later fan out into
// several codes without touching the enum. Every branch resolves to a real code
// so no raw `error.XxxYyy` name can reach the user; unknown values fall back to
// a stage-appropriate catch-all rather than leaking.

/// Reader-stage error -> KP1xxx code.
pub fn readErrorCode(err: anyerror) Code {
    return switch (err) {
        error.UnexpectedEof => .unexpected_eof,
        error.UnexpectedChar => .unexpected_char,
        error.UnexpectedRightParen => .unexpected_right_paren,
        error.InvalidNumber => .invalid_number,
        error.InvalidCharacterName => .invalid_character_name,
        error.UnterminatedString => .unterminated_string,
        error.InvalidEscape => .invalid_escape,
        error.DotNotInList => .dot_outside_list,
        error.NestingTooDeep => .nesting_too_deep,
        error.TokenTooLong => .token_too_long,
        error.OutOfMemory => .out_of_memory,
        else => .unexpected_char,
    };
}

/// Expand/compile-stage error -> KP2xxx code. Callers that already have a
/// syntax-error detail string should use `.syntax_error` directly instead.
pub fn compileErrorCode(err: anyerror) Code {
    return switch (err) {
        error.InvalidSyntax, error.UndefinedVariable, error.JumpOutOfRange => .invalid_syntax,
        error.MacroExpansionLimit => .macro_expansion_limit,
        error.NoMatchingPattern,
        error.EllipsisCountMismatch,
        error.EllipsisDepthMismatch,
        error.PatternTooComplex,
        error.ScopeTableFull,
        => .syntax_error,
        error.TooManyConstants, error.TooManyLocals, error.InternalLimit, error.InvalidBytecode => .internal_error,
        error.OutOfMemory => .out_of_memory,
        else => .invalid_syntax,
    };
}

/// Runtime-stage error -> KP3xxx code. Control-flow signals (Yielded,
/// ContinuationInvoked, Terminated) are not diagnostics and should never reach
/// the reporting layer; if one does it falls to `.uncategorized`.
pub fn runtimeErrorCode(err: anyerror) Code {
    return switch (err) {
        error.ExceptionRaised => .uncaught_exception,
        error.UndefinedVariable => .undefined_variable,
        error.TypeError => .type_error,
        error.ArityMismatch => .arity_mismatch,
        error.DivisionByZero => .division_by_zero,
        error.NotAProcedure => .not_a_procedure,
        error.IndexOutOfBounds => .index_out_of_bounds,
        error.InvalidArgument => .invalid_argument,
        error.StackOverflow => .stack_overflow,
        error.ExecutionTimeout => .execution_timeout,
        error.OutOfMemory => .out_of_memory,
        error.InvalidBytecode => .internal_error,
        error.CompileError => .invalid_syntax,
        else => .uncategorized,
    };
}

// -- Registry integrity (compile-time gate) ---------------------------------
//
// Enforces the invariants KEP-0005 §5 asks a CI gate to check, but at build
// time: every code has exactly one entry, no two entries collide, and every
// entry carries a name, template, and explanation.
comptime {
    for (std.enums.values(Code)) |c| {
        var count: usize = 0;
        for (table) |d| {
            if (d.code == c) count += 1;
        }
        if (count == 0) @compileError("diagnostics registry: code '" ++ @tagName(c) ++ "' has no table entry");
        if (count > 1) @compileError("diagnostics registry: code '" ++ @tagName(c) ++ "' has duplicate table entries");
    }
    for (table) |d| {
        if (d.name.len == 0) @compileError("diagnostics registry: entry '" ++ @tagName(d.code) ++ "' has an empty name");
        if (d.template.len == 0) @compileError("diagnostics registry: entry '" ++ @tagName(d.code) ++ "' has an empty template");
        if (d.explanation.len == 0) @compileError("diagnostics registry: entry '" ++ @tagName(d.code) ++ "' has an empty explanation");
        if (d.example.len == 0) @compileError("diagnostics registry: entry '" ++ @tagName(d.code) ++ "' has an empty example");
    }
}
