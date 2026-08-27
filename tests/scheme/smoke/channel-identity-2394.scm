;; Regression tests for kaappi#2394 (KEP-0002 §2): channel identity across
;; stubs. Two stubs for one SharedChannel are distinct heap objects, so
;; eq?/eqv?/equal? report #f for "the same channel" seen from two receipts —
;; the divergence the KEP's 2026-08-27 as-implemented amendment records.
;; channel=?/channel-hash/channel-comparator are the supported identity
;; surface: they compare (and hash) the `shared` pointer, the one
;; representation every thread agrees on.
;;
;; The channels here are CAPTURED by the thread thunks (let-bound) — the §2
;; legal sharing path that promotes them; a top-level global would fail the
;; foreign-owner check on the child instead. (srfi 69) and (srfi 128) both
;; export string-hash/string-ci-hash, so the table and comparator names are
;; imported with `only` rather than wholesale.
(import (scheme base) (scheme write) (scheme process-context)
        (kaappi fibers) (srfi 18) (srfi 64)
        (only (srfi 69) make-hash-table hash-table-set! hash-table-size
              hash-table-ref/default hash)
        (only (srfi 128) comparator? comparator-type-test-predicate
              comparator-equality-predicate comparator-ordered? comparator-hash))

(test-begin "channel-identity-2394")

;; --- local (unpromoted) channels: pointer identity, hash consistency ---
(define C (make-channel))
(test-equal "channel=? on the same local channel" #t (channel=? C C))

(test-equal "channel=? on two distinct local channels"
  #f (let ((a (make-channel)) (b (make-channel))) (channel=? a b)))

(test-equal "channel-hash is stable and bound form stays in range"
  '(#t #t)
  (let ((a (make-channel)))
    (list (= (channel-hash a) (channel-hash a))
          (< (channel-hash a 100) 100))))

(test-equal "an unshared channel hashes like plain (hash ch)"
  #t (let ((a (make-channel))) (= (channel-hash a) (hash a))))

;; A worker that receives `ch` from to-w and sends it back twice through
;; to-p: the parent ends up holding two stubs of one promoted channel, plus
;; the (in-place-promoted) original.
(define (make-stub-pair)
  (let ((ch (make-channel))
        (to-w (make-channel))
        (to-p (make-channel)))
    (define worker
      (thread-start! (make-thread
        (lambda ()
          (let ((c (channel-receive to-w)))
            (channel-send to-p c)
            (channel-send to-p c))))))
    (channel-send to-w ch)
    (thread-join! worker)
    (cons ch (cons (channel-receive to-p) (channel-receive to-p)))))

;; --- the core scenario: eq?/eqv? cannot unify the stubs; channel=? must,
;; against each other AND the original handle.
(test-equal "stubs of one promoted channel unify under channel=?"
  '(#t #t #t)
  (let* ((triple (make-stub-pair))
         (ch (car triple))
         (a (cadr triple))
         (b (cddr triple)))
    (list (channel=? a b) (channel=? a ch) (channel=? b ch))))

(test-equal "stub and original hash alike once promoted"
  #t
  (let* ((triple (make-stub-pair))
         (ch (car triple))
         (a (cadr triple)))
    (= (channel-hash a) (channel-hash ch))))

;; --- the reply-channel registry idiom the issue exists for ---
(test-equal "make-hash-table with channel=?/channel-hash dedups stubs"
  '(1 second)
  (let* ((triple (make-stub-pair))
         (registry (make-hash-table channel=? channel-hash)))
    (hash-table-set! registry (cadr triple) 'first)
    (hash-table-set! registry (cddr triple) 'second)
    (list (hash-table-size registry)
          (hash-table-ref/default registry (car triple) 'MISS))))

(test-equal "make-hash-table with channel-comparator dedups stubs"
  '(1 3)
  (let* ((triple (make-stub-pair))
         (registry (make-hash-table (channel-comparator))))
    (hash-table-set! registry (car triple) 1)
    (hash-table-set! registry (cadr triple) 2)
    (hash-table-set! registry (cddr triple) 3)
    (list (hash-table-size registry)
          (hash-table-ref/default registry (cadr triple) 'MISS))))

;; --- channel-comparator is a real SRFI-128 comparator ---
(test-equal "comparator fields agree with their channel=?/channel-hash sources"
  '(#t #t #f #f #t)
  (let* ((cmp (channel-comparator))
         (ch (make-channel)))
    (list (comparator? cmp)
          ((comparator-type-test-predicate cmp) ch)
          ((comparator-type-test-predicate cmp) 5)
          (comparator-ordered? cmp)
          (= (comparator-hash cmp ch) (channel-hash ch)))))

(test-equal "comparator equality unifies stubs like channel=?"
  #t
  (let* ((triple (make-stub-pair)))
    ((comparator-equality-predicate (channel-comparator))
     (cadr triple) (cddr triple))))

;; --- argument discipline ---
(define (code-of thunk) (guard (e (#t (error-object-code e))) (thunk) 'no-raise))

(test-equal "type and range errors carry their codes"
  '(KP3002 KP3002 KP3007)
  (let ((ch (make-channel)))
    (list (code-of (lambda () (channel=? ch 5)))
          (code-of (lambda () (channel-hash "x")))
          (code-of (lambda () (channel-hash ch 0))))))

(let ((runner (test-runner-current)))
  (test-end "channel-identity-2394")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
