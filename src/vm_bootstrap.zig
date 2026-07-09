const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;

/// Scheme-level implementations of higher-order procedures that must drive
/// callbacks through the bytecode dispatch loop (not the Zig call stack) so
/// that fibers can park and continuations can be captured/restored inside
/// callbacks. Called at init time between registerAll() and
/// registerStandardLibraries(). Each (define ...) overwrites the native
/// version already in vm.globals.
pub fn install(vm: *VM) VMError!void {
    inline for (definitions) |src| {
        _ = try vm.eval(src);
    }
}

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
    \\(define (for-each proc . lists)
    \\  (if (null? (cdr lists))
    \\      (let loop ((lst (car lists)))
    \\        (if (pair? lst)
    \\            (begin (proc (car lst)) (loop (cdr lst)))
    \\            (if (null? lst)
    \\                (if #f #f)
    \\                (error "for-each: not a proper list"))))
    \\      (let loop ((lsts lists))
    \\        (let ((go (let check ((l lsts))
    \\                    (if (null? l) #t
    \\                        (if (null? (car l)) #f
    \\                            (if (not (pair? (car l)))
    \\                                (error "for-each: not a proper list")
    \\                                (check (cdr l))))))))
    \\          (when go
    \\            (apply proc
    \\              (let cars ((l lsts))
    \\                (if (null? l) '()
    \\                    (cons (car (car l)) (cars (cdr l))))))
    \\            (loop
    \\              (let cdrs ((l lsts))
    \\                (if (null? l) '()
    \\                    (cons (cdr (car l)) (cdrs (cdr l)))))))))))
;

const map_src =
    \\(define (map proc . lists)
    \\  (if (null? (cdr lists))
    \\      (let loop ((lst (car lists)) (acc '()))
    \\        (if (pair? lst)
    \\            (loop (cdr lst) (cons (proc (car lst)) acc))
    \\            (if (null? lst)
    \\                (reverse acc)
    \\                (error "map: not a proper list"))))
    \\      (let loop ((lsts lists) (acc '()))
    \\        (let ((go (let check ((l lsts))
    \\                    (if (null? l) #t
    \\                        (if (null? (car l)) #f
    \\                            (if (not (pair? (car l)))
    \\                                (error "map: not a proper list")
    \\                                (check (cdr l))))))))
    \\          (if go
    \\              (loop
    \\                (let cdrs ((l lsts))
    \\                  (if (null? l) '()
    \\                      (cons (cdr (car l)) (cdrs (cdr l)))))
    \\                (cons
    \\                  (apply proc
    \\                    (let cars ((l lsts))
    \\                      (if (null? l) '()
    \\                          (cons (car (car l)) (cars (cdr l))))))
    \\                  acc))
    \\              (reverse acc))))))
;

const vector_for_each_src =
    \\(define (vector-for-each proc . vecs)
    \\  (let ((len (let min-len ((v vecs) (m #f))
    \\              (if (null? v) m
    \\                  (let ((n (vector-length (car v))))
    \\                    (min-len (cdr v) (if (or (not m) (< n m)) n m)))))))
    \\    (if (null? (cdr vecs))
    \\        (let ((vec (car vecs)))
    \\          (do ((i 0 (+ i 1))) ((>= i len))
    \\            (proc (vector-ref vec i))))
    \\        (do ((i 0 (+ i 1))) ((>= i len))
    \\          (apply proc
    \\            (let refs ((v vecs))
    \\              (if (null? v) '()
    \\                  (cons (vector-ref (car v) i)
    \\                        (refs (cdr v))))))))))
;

const vector_map_src =
    \\(define (vector-map proc . vecs)
    \\  (let* ((len (let min-len ((v vecs) (m #f))
    \\               (if (null? v) m
    \\                   (let ((n (vector-length (car v))))
    \\                     (min-len (cdr v) (if (or (not m) (< n m)) n m))))))
    \\         (result (make-vector len)))
    \\    (if (null? (cdr vecs))
    \\        (let ((vec (car vecs)))
    \\          (do ((i 0 (+ i 1))) ((>= i len))
    \\            (vector-set! result i (proc (vector-ref vec i)))))
    \\        (do ((i 0 (+ i 1))) ((>= i len))
    \\          (vector-set! result i
    \\            (apply proc
    \\              (let refs ((v vecs))
    \\                (if (null? v) '()
    \\                    (cons (vector-ref (car v) i)
    \\                          (refs (cdr v)))))))))
    \\    result))
;

const string_for_each_src =
    \\(define (string-for-each proc . strs)
    \\  (let ((len (let min-len ((s strs) (m #f))
    \\              (if (null? s) m
    \\                  (let ((n (string-length (car s))))
    \\                    (min-len (cdr s) (if (or (not m) (< n m)) n m)))))))
    \\    (if (null? (cdr strs))
    \\        (let ((str (car strs)))
    \\          (do ((i 0 (+ i 1))) ((>= i len))
    \\            (proc (string-ref str i))))
    \\        (do ((i 0 (+ i 1))) ((>= i len))
    \\          (apply proc
    \\            (let refs ((s strs))
    \\              (if (null? s) '()
    \\                  (cons (string-ref (car s) i)
    \\                        (refs (cdr s))))))))))
;

const string_map_src =
    \\(define (string-map proc . strs)
    \\  (let ((len (let min-len ((s strs) (m #f))
    \\              (if (null? s) m
    \\                  (let ((n (string-length (car s))))
    \\                    (min-len (cdr s) (if (or (not m) (< n m)) n m)))))))
    \\    (list->string
    \\      (let loop ((i 0) (acc '()))
    \\        (if (>= i len)
    \\            (reverse acc)
    \\            (loop (+ i 1)
    \\              (cons
    \\                (if (null? (cdr strs))
    \\                    (proc (string-ref (car strs) i))
    \\                    (apply proc
    \\                      (let refs ((s strs))
    \\                        (if (null? s) '()
    \\                            (cons (string-ref (car s) i)
    \\                                  (refs (cdr s)))))))
    \\                acc)))))))
;

const dynamic_wind_src =
    \\(define (dynamic-wind before thunk after)
    \\  (before)
    \\  (%push-wind before after)
    \\  (let ((result (thunk)))
    \\    (%pop-wind)
    \\    (after)
    \\    result))
;

const force_src =
    \\(define (force p)
    \\  (if (not (promise? p)) p
    \\      (let loop ((current p))
    \\        (if (not (promise? current)) current
    \\            (if (%promise-forced? current)
    \\                (loop (%promise-value current))
    \\                (let ((thunk (%promise-value current)))
    \\                  (if (not (procedure? thunk))
    \\                      (begin (%promise-complete! current thunk) thunk)
    \\                      (begin
    \\                        (%promise-set-forcing! current #t)
    \\                        (let ((result (thunk)))
    \\                          (if (%promise-forced? current)
    \\                              (begin
    \\                                (%promise-set-forcing! current #f)
    \\                                (loop (%promise-value current)))
    \\                              (if (promise? result)
    \\                                  (if (%promise-forcing? result)
    \\                                      (begin
    \\                                        (%promise-set-forcing! current #f)
    \\                                        (error "re-entrant forcing of promise"))
    \\                                      (if (%promise-forced? result)
    \\                                          (begin
    \\                                            (%promise-set-forcing! current #f)
    \\                                            (%promise-complete! current (%promise-value result))
    \\                                            (loop (%promise-value result)))
    \\                                          (begin
    \\                                            (%promise-merge! current result)
    \\                                            (loop current))))
    \\                                  (begin
    \\                                    (%promise-set-forcing! current #f)
    \\                                    (%promise-complete! current result)
    \\                                    result))))))))))))
;
