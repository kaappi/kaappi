;; Regression test for #1935: symbol interning was one thread level deep.
;;
;; GC.initForThread pointed a child at its IMMEDIATE parent's symbol table,
;; so a grandchild (child of a child) interned into the middle GC's own
;; `symbols` field -- which stays permanently empty, because the middle's own
;; internings go to its `shared_symbols` -- a table nothing else consults.
;; R7RS 6.5 requires (eq? 'alpha (string->symbol "alpha")) to be #t; at
;; thread depth 2 it was #f, and a symbol a grandchild wrote into a parent
;; object corrupted (the depth-1 ownership stamping that makes symbols the
;; one safe cross-heap write did not reach depth 2).
;;
;; Fix: initForThread chains every descendant to the ROOT's symbol table,
;; foreign_symbols and owner id, so identity holds at any depth and the root
;; owns and frees every interned symbol.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18) (srfi 64))

(test-begin "srfi18-symbol-interning-grandchild-1935")

(define alpha 'alpha)

;; depth 1 -- child
(test-assert "depth 1: (eq? alpha (string->symbol \"alpha\"))"
  (thread-join! (thread-start! (make-thread
    (lambda () (eq? alpha (string->symbol "alpha")))))))

;; depth 2 -- grandchild (the issue's repro)
(test-assert "depth 2: (eq? alpha (string->symbol \"alpha\"))"
  (thread-join! (thread-start! (make-thread (lambda ()
    (let ((g (make-thread (lambda ()
                (eq? alpha (string->symbol "alpha"))))))
      (thread-start! g) (thread-join! g)))))))

;; depth 3 -- great-grandchild
(test-assert "depth 3: (eq? alpha (string->symbol \"alpha\"))"
  (thread-join! (thread-start! (make-thread (lambda ()
    (let ((g (make-thread (lambda ()
              (let ((gg (make-thread (lambda ()
                          (eq? alpha (string->symbol "alpha"))))))
                (thread-start! gg) (thread-join! gg))))))
      (thread-start! g) (thread-join! g)))))))

;; A name NO thread has interned yet: the deepest thread interns it, hands it
;; back via the join, and the root-side intern must dedupe to the same object
;; (deep copy of an interned symbol re-interns by name in the destination --
;; the root's -- table).
(define deep-name
  (thread-join! (thread-start! (make-thread (lambda ()
    (let ((g (make-thread (lambda ()
              (let ((gg (make-thread (lambda ()
                          (string->symbol "never-seen-name")))))
                (thread-start! gg) (thread-join! gg))))))
      (thread-start! g) (thread-join! g)))))))
(test-assert "a name interned at depth 3 is eq? to a root-side intern of the same name"
  (eq? deep-name (string->symbol "never-seen-name")))

;; The corruption control from the issue: a grandchild writes a symbol into a
;; PARENT-heap object (a shared top-level global). The depth-1 ownership
;; stamping made symbols the one safe cross-heap write; it must hold at depth
;; 2 too -- the written symbol is owned by the root, so the parent's own
;; intern of the same name is the same object, and nothing dangles past the
;; joins. Every level joins its child before returning, so the outer join
;; guarantees the write has happened before the parent reads the pair.
(define shared-pair (list 'a 'b))
(define (grandchild-writes-symbol!)
  (let ((t (make-thread
            (lambda ()
              (let ((g (make-thread (lambda ()
                          (set-car! shared-pair (string->symbol "written-through"))))))
                (thread-start! g) (thread-join! g)))
            )))
    (thread-start! t)
    (thread-join! t))
  'done)
(test-equal "grandchild writes a symbol into a shared parent object"
  'done (thread-join! (thread-start! (make-thread grandchild-writes-symbol!))))
(test-assert "the parent reads back the SAME interned symbol the grandchild wrote"
  (eq? (car shared-pair) (string->symbol "written-through")))

;; Control: depth-1 ownership behavior is unchanged (symbols interned by a
;; child survive the join and dedupe with the parent's).
(test-assert "depth 1 control: child-interned name dedupes with the parent's"
  (eq? (thread-join! (thread-start! (make-thread (lambda ()
          (string->symbol "child-interned")))))
       (string->symbol "child-interned")))

(let ((runner (test-runner-current)))
  (test-end "srfi18-symbol-interning-grandchild-1935")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
