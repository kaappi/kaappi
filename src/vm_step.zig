//! Bounded-step, resumable top-level execution (kaappi#2283).
//!
//! `Stepper` drives a whole program the way `main.runFile` does — read a
//! top-level form, run library declarations to completion, compile ordinary
//! forms and execute them — but each `step(budget)` call runs at most `budget`
//! bytecode instructions and then hands control back, whether the program is
//! finished or merely paused mid-form. A host (the browser playground first of
//! all; see the issue and kaappi.github.io#32) pumps `step` in a loop, draining
//! streamed stdout and checking a Stop flag between chunks, so a legitimately
//! long-running, constant-space program such as
//!
//!     ((call/cc call/cc) (call/cc call/cc))
//!
//! runs indefinitely without a hard kill, instead of only being killable by a
//! wall-clock `terminate()` that discards output already produced.
//!
//! The heavy lifting lives in the VM: `beginStep`/`resumeStep` (vm_calls.zig)
//! pause at the dispatch-loop safepoint and keep every stack in the VM struct.
//! This file is the top-level orchestration: form iteration, the compile step,
//! REPL-style result echoing, and error reporting — matching `runFile` so the
//! stepped and batch paths produce identical output.

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const Value = types.Value;
const VMError = vm_mod.VMError;
const vm_calls = @import("vm_calls.zig");
const reader = @import("reader.zig");
const compiler = @import("compiler.zig");
const toplevel_driver = @import("toplevel_driver.zig");
const printer = @import("printer.zig");
const reporting = @import("reporting.zig");

/// What a single `step` produced.
pub const StepOutcome = enum {
    /// The budget was exhausted (or a form paused); call `step` again to
    /// continue. More program remains.
    running,
    /// The whole program has finished (reader drained, no form in progress).
    /// `hadError` reports whether any form errored along the way.
    done,
};

pub const Stepper = struct {
    vm: *VM,
    source: []const u8,
    path: []const u8,
    r: reader.Reader,
    /// A compiled form is paused mid-execution, awaiting `resumeStep`.
    in_progress: bool = false,
    /// The reader is drained (or hit a fatal read error); no more forms.
    finished: bool = false,
    /// Any top-level read/compile/runtime error was seen (batch exit-1 parity).
    had_error: bool = false,
    /// Host-set cooperative-stop flag, wired to `vm.terminate_flag` so the
    /// safepoint sees it. Set by `requestStop`, polled between instructions.
    stop_flag: bool = false,
    saved_terminate_flag: ?*bool = null,

    /// Initialize in place: `stop_flag` is wired into `vm.terminate_flag` by
    /// address, so the `Stepper` must live at its final location before this
    /// runs (a by-value return would leave the flag pointing at a dead frame).
    /// The program text and `path` (used for diagnostics and to resolve
    /// top-level `(include ...)`) must outlive the stepper — it borrows both.
    pub fn init(self: *Stepper, vm: *VM, source: []const u8, path: []const u8) void {
        self.* = .{
            .vm = vm,
            .source = source,
            .path = path,
            .r = reader.Reader.initWithName(vm.gc, source, path),
        };
        // Resolve top-level `(include ...)` relative to the program directory,
        // exactly as runFile does.
        vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
        // Route the cooperative-stop flag through the same terminate path the
        // SRFI-18 safepoint already polls (returns error.Terminated).
        self.saved_terminate_flag = vm.terminate_flag;
        vm.terminate_flag = &self.stop_flag;
    }

    pub fn deinit(self: *Stepper) void {
        self.r.deinit();
        self.vm.terminate_flag = self.saved_terminate_flag;
        self.vm.step_deadline = null;
    }

    /// Request cooperative termination. The next `step` unwinds the running
    /// form at the safepoint (running its dynamic-wind after-thunks) and the
    /// program reports as finished. Safe to call between steps.
    pub fn requestStop(self: *Stepper) void {
        @atomicStore(bool, &self.stop_flag, true, .monotonic);
    }

    /// Run at most `budget` bytecode instructions, then return. `budget` is
    /// shared across every quick form and the tail of a paused one within this
    /// call, so a pump loop makes steady, bounded progress regardless of how
    /// the program is split into top-level forms.
    pub fn step(self: *Stepper, budget: u64) StepOutcome {
        const vm = self.vm;
        if (self.finished) return .done;
        // The safepoint only tests the deadline every 1024 instructions, so a
        // smaller budget cannot pause any earlier — and a zero budget would
        // otherwise make `step` return .running without reading a single form,
        // leaving a host that pumps `kaappi_step_run(0)` spinning forever.
        const deadline = vm.instruction_counter +| @max(budget, 1024);

        // 1. Resume a form paused by a prior step, if any.
        if (self.in_progress) {
            self.in_progress = false;
            var out: Value = types.VOID;
            if (vm.resumeStep(deadline, &out)) |status| {
                switch (status) {
                    .paused => {
                        self.in_progress = true;
                        return .running;
                    },
                    .done => self.emitResult(out),
                }
            } else |err| {
                if (self.reportRunError(err)) return .done;
            }
        }

        // 2. Read and run subsequent forms until the budget is spent or the
        //    reader drains.
        while (true) {
            if (vm.instruction_counter >= deadline) return .running;

            const has_more = self.r.hasMore() catch |err| {
                const lc = self.r.getLineCol();
                toplevel_driver.reportReadError(self.path, lc.line, lc.col, err);
                self.had_error = true;
                self.finished = true;
                return .done;
            };
            if (!has_more) {
                self.finished = true;
                return .done;
            }

            const datum_lc = self.r.getLineCol();
            var expr = self.r.readDatum() catch |err| {
                const lc = self.r.getLineCol();
                toplevel_driver.reportReadError(self.path, lc.line, lc.col, err);
                self.had_error = true;
                self.finished = true;
                return .done;
            };

            vm.gc.pushRoot(&expr);

            // A top-level declaration (import / define-library / include / …)
            // runs to completion here, unstepped: its library-loading work is
            // not the long-running computation stepping exists to interrupt,
            // and it must complete before the next form is even classified.
            if (vm.topLevelHead(expr)) |head| {
                const top_result = vm.runTopLevelHead(head, expr);
                vm.gc.popRoot();
                const result = top_result catch |err| {
                    self.had_error = true;
                    toplevel_driver.reportRuntimeError(vm, err, .{ .source = self.path, .line = datum_lc.line });
                    continue;
                };
                self.emitResult(result);
                continue;
            }

            const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, self.path, false) catch |err| {
                vm.gc.popRoot();
                toplevel_driver.reportCompileError(self.path, datum_lc.line, datum_lc.col, err);
                self.had_error = true;
                continue;
            };
            vm.gc.popRoot(); // expr

            // `func` stays alive across beginStep's allocClosure without a
            // manual root: compileExpressionWithMacrosAt leaves it in
            // gc.extra_roots on success (Compiler.init). Pushing a second root
            // here would also inflate the root-stack depth beginStep records as
            // the form's base, corrupting a later resumeStep's error unwind.
            var out: Value = types.VOID;
            const begin = vm.beginStep(func, deadline, &out);

            const status = begin catch |err| {
                if (self.reportRunError(err)) return .done;
                continue;
            };
            switch (status) {
                .paused => {
                    self.in_progress = true;
                    return .running;
                },
                .done => self.emitResult(out),
            }
        }
    }

    /// Report a runtime error from a stepped form, mirroring runFile. Returns
    /// true when the error is a cooperative stop (`error.Terminated`) that ends
    /// the program rather than continuing to the next form.
    fn reportRunError(self: *Stepper, err: VMError) bool {
        const vm = self.vm;
        if (err == VMError.Terminated) {
            // Host-requested stop: end quietly, as if the program finished.
            self.finished = true;
            return true;
        }
        self.had_error = true;
        const loc = toplevel_driver.vmErrorLocation(vm, self.path, 0);
        toplevel_driver.reportRuntimeError(vm, err, loc);
        toplevel_driver.printSourceSnippet(self.source, loc.line);
        toplevel_driver.printStackTrace(vm);
        return false;
    }

    /// REPL-style echo of a non-void top-level result, matching runFile's
    /// printTopLevelResult so stepped output equals batch output. Roots the
    /// result: printing allocates, and for a multiple-values result the rooted
    /// container keeps its elements alive across each element's own printing.
    fn emitResult(self: *Stepper, result: Value) void {
        var r = result;
        self.vm.gc.pushRoot(&r);
        defer self.vm.gc.popRoot();
        if (types.isMultipleValues(r)) {
            const mv = types.toObject(r).as(types.MultipleValues);
            for (mv.values) |val| self.emitSingle(val);
        } else {
            self.emitSingle(r);
        }
    }

    fn emitSingle(self: *Stepper, value: Value) void {
        if (value == types.VOID) return;
        const s = printer.valueToString(self.vm.gc.allocator, value, .write) catch return;
        defer self.vm.gc.allocator.free(s);
        reporting.writeStdout(s);
        reporting.writeStdout("\n");
    }
};

test {
    _ = @import("tests_step.zig");
}
