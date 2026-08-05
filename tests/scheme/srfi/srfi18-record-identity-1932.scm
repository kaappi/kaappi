;; Regression test for kaappi#1932 — a record that crosses an SRFI-18 thread
;; boundary keeps its TYPE, not just its printed shape.
;;
;; Record type identity used to be the RecordType pointer, and every copy
;; boundary in gc_deep_copy.zig necessarily allocates a new RecordType in the
;; receiving heap. So `(thread-join! t)` handed back a value that printed as
;; `#<<pt> 1 2>` while `pt?` answered #f and every accessor raised
;; "expected <pt>, got #<record_instance>" — a `cond` dispatching on the
;; predicate silently took the wrong branch. RecordType.identity is the part
;; that now survives the copy (types_record.sameRecordType).
;;
;; All four boundaries are covered: into the child (thunk capture), out of it
;; (join result), the uncaught-exception path, and a channel message. The last
;; one matters because the child is still RUNNING when the parent receives.

(import (scheme base) (scheme write) (srfi 18) (srfi 120))

(define pass-count 0)
(define fail-count 0)

(define (check desc ok?)
  (if ok?
      (set! pass-count (+ pass-count 1))
      (begin (set! fail-count (+ fail-count 1))
             (display "  FAIL: ") (display desc) (newline))))

(define-record-type <pt> (make-pt x y) pt? (x pt-x) (y pt-y))

(define (join-thunk thunk)
  (let ((t (make-thread thunk)))
    (thread-start! t)
    (thread-join! t)))

;; --- OUT: the issue's own reproduction ---------------------------------
(let ((r (join-thunk (lambda () (make-pt 1 2)))))
  (check "OUT: predicate recognises a child-built record" (pt? r))
  (check "OUT: accessors read the fields" (equal? (list (pt-x r) (pt-y r)) '(1 2))))

;; --- IN: the same failure from the other side --------------------------
;; The thunk captures both the instance and (through pt?) the record type, so
;; the child receives copies of each; they must still agree about the type.
(let ((v (make-pt 7 8)))
  (check "IN: captured predicate recognises a parent-built record"
         (equal? (join-thunk (lambda () (list (pt? v) (pt-x v)))) '(#t 7))))

;; --- EXC: the raise path shares the same copy arm ----------------------
(let* ((t (make-thread (lambda () (raise (make-pt 3 4)))))
       (r (guard (e (#t (and (uncaught-exception? e) (uncaught-exception-reason e))))
            (thread-start! t)
            (thread-join! t)
            #f)))
  (check "EXC: a raised record keeps its type" (pt? r))
  (check "EXC: a raised record keeps its fields" (= (pt-y r) 4)))

;; --- CHANNEL: the child is still alive when the parent receives --------
(let ((ch (make-channel)))
  (let ((t (make-thread (lambda () (channel-send ch (make-pt 5 6)) 'sent))))
    (thread-start! t)
    (let ((r (channel-receive ch)))
      (thread-join! t)
      (check "CHANNEL: a messaged record keeps its type" (pt? r))
      (check "CHANNEL: a messaged record keeps its fields"
             (equal? (list (pt-x r) (pt-y r)) '(5 6))))))

;; --- CONTROL: generative semantics are not weakened --------------------
;; `define-record-type` is generative: two evaluations of the SAME form make
;; two distinct types. A fix that made every same-named type interchangeable
;; would pass everything above and break this.
(define (fresh-type)
  (define-record-type <g> (make-g v) g? (v g-v))
  (list (make-g 1) g?))

(let ((a (fresh-type)) (b (fresh-type)))
  (check "CONTROL: a type recognises its own instance" ((cadr a) (car a)))
  (check "CONTROL: a separately defined type does not" (not ((cadr b) (car a))))
  ;; And the distinctness survives the copy, rather than collapsing on the
  ;; far side.
  (check "CONTROL: distinctness survives thread-join!"
         (let ((crossed (join-thunk (lambda () (car a)))))
           (and ((cadr a) crossed) (not ((cadr b) crossed))))))

;; --- CONTROL: a foreign value is still rejected by the predicate -------
(check "CONTROL: predicate rejects a non-record" (not (pt? '(1 2))))
(check "CONTROL: accessor raises on a foreign record"
       (let ((other (car (fresh-type))))
         (guard (e (#t #t)) (pt-x other) #f)))

(display pass-count) (display " pass, ")
(display fail-count) (display " fail") (newline)
(when (> fail-count 0)
  (error "kaappi#1932 record identity tests failed"))
