;; KEP-0002 Phase 5 (#1470): (kaappi parallel) parallel-map / parallel-for-each.
;; Both manage a private pool sized (processor-count) internally: one task
;; per list element (UQ5, resolved in favor of simplicity over N-chunking --
;; see the library's header comment), reassembled in order for free since
;; each element's reply lives on its own channel.

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi parallel) (srfi 1) (srfi 64))

(test-begin "kaappi-parallel-map")

(test-equal "parallel-map preserves list order"
  '(0 1 4 9 16 25 36 49 64 81)
  (parallel-map (lambda (x) (* x x)) '(0 1 2 3 4 5 6 7 8 9)))

(test-equal "parallel-map on an empty list"
  '()
  (parallel-map (lambda (x) (* x x)) '()))

(test-equal "parallel-map on a single-element list"
  '(42)
  (parallel-map (lambda (x) x) '(42)))

(test-assert "an exception from any element propagates out of parallel-map"
  (guard (e (#t #t))
    (parallel-map (lambda (x) (if (= x 3) (error "boom") x)) '(1 2 3 4 5))
    #f))

(test-assert "parallel-map rejects a non-procedure"
  (guard (e (#t #t)) (parallel-map "not-a-procedure" '(1 2 3)) #f))

(test-assert "parallel-for-each calls f on every element exactly once"
  ;; Side effects from pool workers land in a different heap than the
  ;; caller's, so they can't be observed via a shared mutable variable --
  ;; only via a channel, lexically captured (a top-level define would hit
  ;; the "channel reached through a shared global" guard).
  (let ((out (make-channel)))
    (parallel-for-each (lambda (x) (channel-send out (* x 10))) '(1 2 3 4 5))
    (lset= = (list (channel-receive out) (channel-receive out) (channel-receive out)
                    (channel-receive out) (channel-receive out))
           '(10 20 30 40 50))))

(test-equal "parallel-for-each on an empty list calls f zero times"
  0
  (let ((out (make-channel)))
    (parallel-for-each (lambda (x) (channel-send out x)) '())
    (channel-close! out)
    (let loop ((n 0))
      (if (eof-object? (channel-receive out)) n (loop (+ n 1))))))

(test-assert "parallel-for-each rejects a non-procedure"
  (guard (e (#t #t)) (parallel-for-each "not-a-procedure" '(1 2 3)) #f))

(let ((runner (test-runner-current)))
  (test-end "kaappi-parallel-map")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
