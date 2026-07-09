const std = @import("std");
const reporting = @import("reporting.zig");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;

/// Scheme-level implementations of higher-order procedures that must drive
/// callbacks through the bytecode dispatch loop (not the Zig call stack) so
/// that fibers can park and continuations can be captured/restored inside
/// callbacks. Called at init time between registerAll() and
/// registerStandardLibraries(). Each (define ...) overwrites the native
/// stub already in vm.globals (see primitives.bootstrapStub).
///
/// Every definition is wrapped in a `let` that captures its dependencies
/// (car, cdr, apply, %push-wind, ...) as closure upvalues at install time,
/// so a later top-level redefinition of a base binding cannot change the
/// behavior of these procedures — matching the immunity the native
/// implementations had (#1375).
pub fn install(vm: *VM) VMError!void {
    inline for (definitions, 0..) |src, i| {
        _ = vm.eval(src) catch |err| {
            // A failed bootstrap would otherwise abort VM startup with a bare
            // exit code; say which definition broke.
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "vm_bootstrap.install: definition {d} ({s}...) failed: {s}\n", .{ i, src[0..@min(src.len, 24)], @errorName(err) }) catch "vm_bootstrap.install failed\n";
            reporting.writeStderr(msg);
            return err;
        };
    }
    // The %-helpers registered by primitives_control.zig / primitives_lazy.zig
    // exist only to be captured by the closures above. Remove them from the
    // global namespace so they cannot be reached without an import: calling
    // %push-wind without a matching %pop-wind corrupts the wind stack, and
    // the %promise-* mutators can corrupt promise state (#1375).
    {
        vm.globals_lock.lock();
        defer vm.globals_lock.unlock();
        for (internal_helpers) |name| {
            _ = vm.globals.remove(name);
        }
    }
    vm.global_version +%= 1;
}

const internal_helpers = [_][]const u8{
    "%push-wind",
    "%pop-wind",
    "%promise-forced?",
    "%promise-forcing?",
    "%promise-value",
    "%promise-complete!",
    "%promise-set-forcing!",
    "%promise-merge!",
};

const definitions = [_][]const u8{
    for_each_src,
    map_src,
    vector_for_each_src,
    vector_map_src,
    string_for_each_src,
    string_map_src,
    dynamic_wind_src,
    force_src,
};

const for_each_src =
    \\(define for-each
    \\  (let ((null? null?) (pair? pair?) (car car) (cdr cdr) (cons cons)
    \\        (apply apply) (procedure? procedure?) (not not) (error error))
    \\    (lambda (proc list1 . lists)
    \\      (if (not (procedure? proc))
    \\          (error "type error in 'for-each': expected procedure, got" proc))
    \\      (if (null? lists)
    \\          (let loop ((lst list1))
    \\            (if (pair? lst)
    \\                (begin (proc (car lst)) (loop (cdr lst)))
    \\                (if (null? lst)
    \\                    (if #f #f)
    \\                    (error "for-each: not a proper list"))))
    \\          (let loop ((lsts (cons list1 lists)))
    \\            (let ((go (let check ((l lsts))
    \\                        (if (null? l) #t
    \\                            (if (null? (car l)) #f
    \\                                (if (not (pair? (car l)))
    \\                                    (error "for-each: not a proper list")
    \\                                    (check (cdr l))))))))
    \\              (when go
    \\                (apply proc
    \\                  (let cars ((l lsts))
    \\                    (if (null? l) '()
    \\                        (cons (car (car l)) (cars (cdr l))))))
    \\                (loop
    \\                  (let cdrs ((l lsts))
    \\                    (if (null? l) '()
    \\                        (cons (cdr (car l)) (cdrs (cdr l)))))))))))))
;

const map_src =
    \\(define map
    \\  (let ((null? null?) (pair? pair?) (car car) (cdr cdr) (cons cons)
    \\        (reverse reverse) (apply apply) (procedure? procedure?)
    \\        (not not) (error error))
    \\    (lambda (proc list1 . lists)
    \\      (if (not (procedure? proc))
    \\          (error "type error in 'map': expected procedure, got" proc))
    \\      (if (null? lists)
    \\          (let loop ((lst list1) (acc '()))
    \\            (if (pair? lst)
    \\                (loop (cdr lst) (cons (proc (car lst)) acc))
    \\                (if (null? lst)
    \\                    (reverse acc)
    \\                    (error "map: not a proper list"))))
    \\          (let loop ((lsts (cons list1 lists)) (acc '()))
    \\            (let ((go (let check ((l lsts))
    \\                        (if (null? l) #t
    \\                            (if (null? (car l)) #f
    \\                                (if (not (pair? (car l)))
    \\                                    (error "map: not a proper list")
    \\                                    (check (cdr l))))))))
    \\              (if go
    \\                  (loop
    \\                    (let cdrs ((l lsts))
    \\                      (if (null? l) '()
    \\                          (cons (cdr (car l)) (cdrs (cdr l)))))
    \\                    (cons
    \\                      (apply proc
    \\                        (let cars ((l lsts))
    \\                          (if (null? l) '()
    \\                              (cons (car (car l)) (cars (cdr l))))))
    \\                      acc))
    \\                  (reverse acc))))))))
;

const vector_for_each_src =
    \\(define vector-for-each
    \\  (let ((null? null?) (car car) (cdr cdr) (cons cons) (apply apply)
    \\        (vector-length vector-length) (vector-ref vector-ref)
    \\        (procedure? procedure?) (not not) (error error)
    \\        (< <) (>= >=) (+ +))
    \\    (lambda (proc vec1 . vecs)
    \\      (if (not (procedure? proc))
    \\          (error "type error in 'vector-for-each': expected procedure, got" proc))
    \\      (if (null? vecs)
    \\          (let ((len (vector-length vec1)))
    \\            (do ((i 0 (+ i 1))) ((>= i len))
    \\              (proc (vector-ref vec1 i))))
    \\          (let ((len (let min-len ((v vecs) (m (vector-length vec1)))
    \\                       (if (null? v) m
    \\                           (let ((n (vector-length (car v))))
    \\                             (min-len (cdr v) (if (< n m) n m))))))
    \\                (all (cons vec1 vecs)))
    \\            (do ((i 0 (+ i 1))) ((>= i len))
    \\              (apply proc
    \\                (let refs ((v all))
    \\                  (if (null? v) '()
    \\                      (cons (vector-ref (car v) i)
    \\                            (refs (cdr v))))))))))))
;

const vector_map_src =
    \\(define vector-map
    \\  (let ((null? null?) (car car) (cdr cdr) (cons cons) (apply apply)
    \\        (vector-length vector-length) (vector-ref vector-ref)
    \\        (vector-set! vector-set!) (make-vector make-vector)
    \\        (procedure? procedure?) (not not) (error error)
    \\        (< <) (>= >=) (+ +))
    \\    (lambda (proc vec1 . vecs)
    \\      (if (not (procedure? proc))
    \\          (error "type error in 'vector-map': expected procedure, got" proc))
    \\      (if (null? vecs)
    \\          (let* ((len (vector-length vec1))
    \\                 (result (make-vector len)))
    \\            (do ((i 0 (+ i 1))) ((>= i len))
    \\              (vector-set! result i (proc (vector-ref vec1 i))))
    \\            result)
    \\          (let* ((len (let min-len ((v vecs) (m (vector-length vec1)))
    \\                        (if (null? v) m
    \\                            (let ((n (vector-length (car v))))
    \\                              (min-len (cdr v) (if (< n m) n m))))))
    \\                 (all (cons vec1 vecs))
    \\                 (result (make-vector len)))
    \\            (do ((i 0 (+ i 1))) ((>= i len))
    \\              (vector-set! result i
    \\                (apply proc
    \\                  (let refs ((v all))
    \\                    (if (null? v) '()
    \\                        (cons (vector-ref (car v) i)
    \\                              (refs (cdr v))))))))
    \\            result)))))
;

const string_for_each_src =
    \\(define string-for-each
    \\  (let ((null? null?) (car car) (cdr cdr) (cons cons) (apply apply)
    \\        (string-length string-length) (string-ref string-ref)
    \\        (procedure? procedure?) (not not) (error error)
    \\        (< <) (>= >=) (+ +))
    \\    (lambda (proc str1 . strs)
    \\      (if (not (procedure? proc))
    \\          (error "type error in 'string-for-each': expected procedure, got" proc))
    \\      (if (null? strs)
    \\          (let ((len (string-length str1)))
    \\            (do ((i 0 (+ i 1))) ((>= i len))
    \\              (proc (string-ref str1 i))))
    \\          (let ((len (let min-len ((s strs) (m (string-length str1)))
    \\                       (if (null? s) m
    \\                           (let ((n (string-length (car s))))
    \\                             (min-len (cdr s) (if (< n m) n m))))))
    \\                (all (cons str1 strs)))
    \\            (do ((i 0 (+ i 1))) ((>= i len))
    \\              (apply proc
    \\                (let refs ((s all))
    \\                  (if (null? s) '()
    \\                      (cons (string-ref (car s) i)
    \\                            (refs (cdr s))))))))))))
;

const string_map_src =
    \\(define string-map
    \\  (let ((null? null?) (car car) (cdr cdr) (cons cons) (apply apply)
    \\        (string-length string-length) (string-ref string-ref)
    \\        (list->string list->string) (reverse reverse)
    \\        (procedure? procedure?) (not not) (error error)
    \\        (< <) (>= >=) (+ +))
    \\    (lambda (proc str1 . strs)
    \\      (if (not (procedure? proc))
    \\          (error "type error in 'string-map': expected procedure, got" proc))
    \\      (let ((len (if (null? strs)
    \\                     (string-length str1)
    \\                     (let min-len ((s strs) (m (string-length str1)))
    \\                       (if (null? s) m
    \\                           (let ((n (string-length (car s))))
    \\                             (min-len (cdr s) (if (< n m) n m)))))))
    \\            (all (cons str1 strs)))
    \\        (list->string
    \\          (let loop ((i 0) (acc '()))
    \\            (if (>= i len)
    \\                (reverse acc)
    \\                (loop (+ i 1)
    \\                  (cons
    \\                    (if (null? strs)
    \\                        (proc (string-ref str1 i))
    \\                        (apply proc
    \\                          (let refs ((s all))
    \\                            (if (null? s) '()
    \\                                (cons (string-ref (car s) i)
    \\                                      (refs (cdr s)))))))
    \\                    acc)))))))))
;

// Validates all three arguments before running (before), so a bad-argument
// call cannot leak before's side effects, and errors name 'dynamic-wind'
// rather than the internal %push-wind (#1375).
const dynamic_wind_src =
    \\(define dynamic-wind
    \\  (let ((%push-wind %push-wind) (%pop-wind %pop-wind)
    \\        (procedure? procedure?) (not not) (error error))
    \\    (lambda (before thunk after)
    \\      (if (not (procedure? before))
    \\          (error "type error in 'dynamic-wind': expected procedure, got" before))
    \\      (if (not (procedure? thunk))
    \\          (error "type error in 'dynamic-wind': expected procedure, got" thunk))
    \\      (if (not (procedure? after))
    \\          (error "type error in 'dynamic-wind': expected procedure, got" after))
    \\      (before)
    \\      (%push-wind before after)
    \\      (let ((result (thunk)))
    \\        (%pop-wind)
    \\        (after)
    \\        result))))
;

const force_src =
    \\(define force
    \\  (let ((promise? promise?) (procedure? procedure?) (not not)
    \\        (dynamic-wind dynamic-wind) (error error)
    \\        (%promise-forced? %promise-forced?)
    \\        (%promise-forcing? %promise-forcing?)
    \\        (%promise-value %promise-value)
    \\        (%promise-complete! %promise-complete!)
    \\        (%promise-set-forcing! %promise-set-forcing!)
    \\        (%promise-merge! %promise-merge!))
    \\    (lambda (p)
    \\      (if (not (promise? p)) p
    \\          (let loop ((current p))
    \\            (if (not (promise? current)) current
    \\                (if (%promise-forced? current)
    \\                    (loop (%promise-value current))
    \\                    (let ((thunk (%promise-value current)))
    \\                      (if (not (procedure? thunk))
    \\                          (begin (%promise-complete! current thunk) thunk)
    \\                          (begin
    \\                            (%promise-set-forcing! current #t)
    \\                            ;; Clear `forcing` on ABNORMAL exit only (raise or
    \\                            ;; call/cc escape), matching the native forceFn's
    \\                            ;; `catch |err|`. Normal returns keep it set so the
    \\                            ;; (%promise-forcing? result) cycle check below can
    \\                            ;; see it; the exit paths clear it explicitly.
    \\                            (let* ((ok #f)
    \\                                   (result
    \\                                    (dynamic-wind
    \\                                      (lambda () #f)
    \\                                      (lambda ()
    \\                                        (let ((r (thunk))) (set! ok #t) r))
    \\                                      (lambda ()
    \\                                        (if (not ok)
    \\                                            (%promise-set-forcing! current #f))))))
    \\                              (if (%promise-forced? current)
    \\                                  (begin
    \\                                    (%promise-set-forcing! current #f)
    \\                                    (loop (%promise-value current)))
    \\                                  (if (promise? result)
    \\                                      (if (%promise-forcing? result)
    \\                                          (begin
    \\                                            (%promise-set-forcing! current #f)
    \\                                            (error "re-entrant forcing of promise"))
    \\                                          (if (%promise-forced? result)
    \\                                              (begin
    \\                                                (%promise-set-forcing! current #f)
    \\                                                (%promise-complete! current (%promise-value result))
    \\                                                (loop (%promise-value result)))
    \\                                              (begin
    \\                                                (%promise-merge! current result)
    \\                                                (loop current))))
    \\                                      (begin
    \\                                        (%promise-set-forcing! current #f)
    \\                                        (%promise-complete! current result)
    \\                                        result))))))))))))))
;
