;; Regression test: symbols first interned by an SRFI-18 child thread must be
;; freed at parent teardown, not leaked.
;;
;; A child thread's GC aliases the parent's symbol table via `shared_symbols`.
;; allocSymbol used to skip `trackObject` for a child GC, so a symbol the child
;; interned landed on NO GC's object list: the child's sweep/deinit never freed
;; it (not on its list) and the parent never knew about it. Every distinct
;; symbol first interned by a child thread therefore leaked its Symbol struct
;; plus its name dupe (~2 allocations each). This is orthogonal to issue #797
;; (the allocSymbol data race) — that only changed the locking, not the
;; trackObject decision. The fix hands child-interned symbols to the parent
;; GC's `foreign_symbols` list, which the parent frees at deinit.
;;
;; The child below interns 500 DISTINCT new symbols that the parent never
;; touches, so every one exercises the child-only intern path. The leak is
;; observable only under the Debug leak-checking allocator, by leak count:
;;
;;   zig build run -Doptimize=Debug -- tests/scheme/srfi/srfi18-child-symbol-leak.scm \
;;     2>&1 | grep -c 'leaked:'
;;
;; Before the fix that reports 1002 leaks (1000 from the child symbols — a
;; Symbol struct + name dupe each — plus 2 unrelated pre-existing teardown
;; leaks the interpreter reports for any script). After the fix it reports 2:
;; the child symbols are all reclaimed. Under the default ReleaseSafe build
;; (what run-all.sh uses) there is no leak checker, so the script just runs to
;; completion and prints OK. The mechanical assertion that fails without the
;; fix lives in src/tests_srfi18.zig, which runs the same scenario against a
;; dedicated GC under std.testing.allocator (0 tolerated leaks).

(import (scheme base) (scheme write) (srfi 18))

(define (intern-distinct n prefix)
  (let loop ((i 0))
    (if (< i n)
        (begin
          (string->symbol (string-append prefix (number->string i)))
          (loop (+ i 1)))
        'done)))

(define t (make-thread (lambda () (intern-distinct 500 "child-only-"))))
(define started (thread-start! t))

(unless (eq? (thread-join! t) 'done)
  (display "FAIL: child thread did not complete")
  (newline)
  (exit 1))

(display "OK")
(newline)
