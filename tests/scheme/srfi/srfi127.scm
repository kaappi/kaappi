;; SRFI-127 (lazy sequences) conformance tests — audit Phase 3e
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi127.scm

(import (scheme base) (srfi 127) (chibi test))

(test-begin "srfi-127")

(define (make-gen lst)
  (lambda ()
    (if (null? lst)
        (eof-object)
        (let ((x (car lst))) (set! lst (cdr lst)) x))))

;;; --- construction ---
(test '() (generator->lseq (make-gen '())))
(let ((s (generator->lseq (make-gen '(1 2 3)))))
  (test #t (lseq? s))
  (test 1 (lseq-car s))
  (test 1 (lseq-first s))
  (test 2 (lseq-car (lseq-cdr s)))
  (test '(1 2 3) (lseq->list s)))

;; an ordinary list is an lseq
(test #t (lseq? '(1 2 3)))
(test '(1 2) (lseq->list (list->lseq '(1 2))))

;;; --- laziness: the generator is consumed on demand ---
(define pulls 0)
(define lazy-seq
  (generator->lseq
   (lambda () (set! pulls (+ pulls 1)) (if (> pulls 10) (eof-object) pulls))))
(test 1 pulls)                        ; generator->lseq pulls exactly one
(test 1 (lseq-car lazy-seq))
(test 1 pulls)                        ; car does not pull more

;;; --- operations ---
(define (seq123) (generator->lseq (make-gen '(1 2 3))))
(test 3 (lseq-length (seq123)))
(test '(2 4 6) (lseq->list (lseq-map (lambda (x) (* 2 x)) (seq123))))
(test '(2) (lseq->list (lseq-filter even? (seq123))))
(test '(1 2) (lseq->list (lseq-take (seq123) 2)))
(test '(3) (lseq->list (lseq-drop (seq123) 2)))
(test 2 (lseq-ref (seq123) 1))
(test '(1 2 3 4) (lseq->list (lseq-append (list->lseq '(1 2)) (list->lseq '(3 4)))))
(test #t (lseq-any even? (seq123)))
(test #f (lseq-any (lambda (x) (> x 5)) (seq123)))
(test #t (lseq-every positive? (seq123)))
(test #f (lseq-every even? (seq123)))
(test '(1 2 3)
      (let ((acc '()))
        (lseq-for-each (lambda (x) (set! acc (cons x acc))) (seq123))
        (reverse acc)))
(test #t (lseq=? = (seq123) (seq123)))
(test #f (lseq=? = (seq123) (list->lseq '(1 2))))

;; lseq-realize forces the whole sequence
(test '(1 2 3) (lseq-realize (seq123)))

(test-end "srfi-127")
