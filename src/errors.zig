pub const KaappiError = error{
    StackOverflow,
    TypeError,
    ArityMismatch,
    UndefinedVariable,
    NotAProcedure,
    OutOfMemory,
    InvalidBytecode,
    DivisionByZero,
    CompileError,
    ExceptionRaised,
    ContinuationInvoked,
    IndexOutOfBounds,
    InvalidArgument,
    Yielded,
    ExecutionTimeout,
    Terminated,
};

/// True for errors that are not Scheme conditions: VM resource limits and
/// internal control-flow signals. `with-exception-handler` — and therefore
/// `guard`, which desugars to it — must never turn one of these into an error
/// object a user clause can match.
///
/// Until #1886 it did, and the result was a silently wrong answer: exceeding
/// a VM limit inside nested `guard`s delivered a bare `#<error "error">` to
/// the *enclosing* guard, whose `(#t ...)` clause returned a plausible value
/// with exit 0. A limit of the implementation is not something the program
/// raised, so it unwinds past every handler to the top level, where it is
/// reported under its own code (stack overflow → KP3008, timeout → KP3009).
///
/// Two errors are absent on purpose.
///
/// `ContinuationInvoked` belongs here conceptually, but every catch site must
/// handle it *before* consulting this predicate: it needs its own non-error
/// unwinding, not propagation.
///
/// `OutOfMemory` is overloaded and so stays catchable. It does mean genuine
/// exhaustion (including a `--max-memory` budget), but it is equally what
/// `gc_alloc.max_payload_bytes` returns for `(make-vector 100000000000000)` —
/// a program asking for something impossible, which is an ordinary fault a
/// program may handle. Distinguishing the two means a separate error tag on
/// the size-cap paths; until then, catchable is the safer of two wrong
/// answers (`tests_exceptions.zig` pins the payload-cap half).
///
/// Errors NOT listed here are genuine program faults — type error, arity
/// mismatch, unbound variable, division by zero — and stay catchable, which
/// is the whole point of `guard`.
pub fn isUncatchable(err: KaappiError) bool {
    return switch (err) {
        // Resource limits: the VM ran out of something, not the program.
        error.StackOverflow, error.ExecutionTimeout => true,
        // Control-flow signals: a terminated thread must not run guard
        // clauses on its way out, and a scheduler yield is not a condition.
        error.Terminated, error.Yielded => true,
        else => false,
    };
}
