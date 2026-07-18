;; SRFI-271 (random port libraries) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi271.scm

(import (scheme base)
        (scheme read)
        (scheme write)
        (srfi 64)
        (srfi 271)                         ; alias for randomized
        (prefix (srfi 271 randomized) r:)
        (prefix (srfi 271 determinized) d:))

(test-begin "srfi-271")

;; Read n bytes from a binary input port into a list.
(define (take-bytes p n)
  (let loop ((i 0) (acc '()))
    (if (= i n) (reverse acc) (loop (+ i 1) (cons (read-u8 p) acc)))))

;; #t iff calling thunk raises a random-port-initialization-error.
(define (init-error? thunk)
  (call-with-current-continuation
   (lambda (k)
     (with-exception-handler
      (lambda (e) (k (d:random-port-initialization-error? e)))
      (lambda () (thunk) #f)))))

;; A 32-byte seed of distinct bytes.
(define (ramp-seed)
  (let ((bv (make-bytevector 32 0)))
    (do ((i 0 (+ i 1))) ((= i 32) bv)
      (bytevector-u8-ref bv i)
      (bytevector-u8-set! bv i (modulo (* i 7) 256)))))

;;; --- ports are ordinary binary input ports ------------------------------

(let ((p (make-random-port)))                 ; (srfi 271) == randomized
  (test-assert (port? p))
  (test-assert (input-port? p))
  (test-assert (binary-port? p))
  (test-assert (not (textual-port? p)))
  (test-assert (let ((b (read-u8 p))) (and (exact-integer? b) (<= 0 b 255)))))

(let ((p (r:make-random-port)))
  (test-assert (binary-port? p))
  ;; read-bytevector works and never hits EOF on a random port
  (let ((bv (read-bytevector 64 p)))
    (test-assert (bytevector? bv))
    (test-eqv 64 (bytevector-length bv))))

;;; --- randomized ports are not reproducible ------------------------------

(test-assert
 (not (equal? (take-bytes (r:make-random-port) 16)
              (take-bytes (r:make-random-port) 16))))

;; determinized with no argument is randomly seeded, hence also differs
(test-assert
 (not (equal? (take-bytes (d:make-random-port) 16)
              (take-bytes (d:make-random-port) 16))))

;;; --- determinized ports are reproducible --------------------------------

(let* ((seed (ramp-seed))
       (a (d:make-random-port (open-input-bytevector seed)))
       (b (d:make-random-port (open-input-bytevector seed))))
  (test-equal (take-bytes a 128) (take-bytes b 128)))

;; different seeds give different streams
(let ((a (d:make-random-port (open-input-bytevector (make-bytevector 32 1))))
      (b (d:make-random-port (open-input-bytevector (make-bytevector 32 2)))))
  (test-assert (not (equal? (take-bytes a 32) (take-bytes b 32)))))

;;; --- random-port? -------------------------------------------------------

(let ((d (d:make-random-port (open-input-bytevector (ramp-seed)))))
  (test-assert (d:random-port? d)))
(test-assert (not (d:random-port? (open-input-bytevector #u8(1 2 3)))))
(test-assert (not (d:random-port? 'x)))
(test-assert (not (d:random-port? (d:random-port-state
                                   (d:make-random-port (open-input-bytevector (ramp-seed)))))))

;;; --- state: capture, predicate, equality --------------------------------

(let* ((seed (ramp-seed))
       (p (d:make-random-port (open-input-bytevector seed))))
  (take-bytes p 5)
  (let ((st (d:random-port-state p)))
    (test-assert (d:random-port-state? st))
    ;; snapshotting again from the same state yields an equal state
    (let ((st2 (d:random-port-state (d:make-random-port st))))
      (test-assert (d:random-port-state=? st st2)))
    ;; restoring resumes the identical byte stream
    (let ((q (d:make-random-port st)))
      (test-equal (take-bytes p 64) (take-bytes q 64)))))

;; state=? : zero and one argument are trivially #t; distinct states are #f
(test-assert (d:random-port-state=?))
(let ((st (d:random-port-state (d:make-random-port (open-input-bytevector (ramp-seed))))))
  (test-assert (d:random-port-state=? st))
  (test-assert (d:random-port-state=? st st st)))
(let ((s1 (d:random-port-state (d:make-random-port (open-input-bytevector (make-bytevector 32 1)))))
      (s2 (d:random-port-state (d:make-random-port (open-input-bytevector (make-bytevector 32 2))))))
  (test-assert (not (d:random-port-state=? s1 s2))))

;; state? rejects malformed objects
(test-assert (not (d:random-port-state? #u8(1 2 3))))
(test-assert (not (d:random-port-state? "S271")))
(test-assert (not (d:random-port-state? 42)))

;;; --- state external representation is write/read invariant --------------

(let* ((st (d:random-port-state
            (let ((p (d:make-random-port (open-input-bytevector (ramp-seed)))))
              (take-bytes p 3) p)))
       (text (let ((o (open-output-string))) (write st o) (get-output-string o)))
       (back (read (open-input-string text))))
  (test-assert (d:random-port-state? back))
  (test-assert (d:random-port-state=? st back))
  ;; and the read-back state drives an identical stream
  (test-equal (take-bytes (d:make-random-port st) 32)
              (take-bytes (d:make-random-port back) 32)))

;;; --- initialization errors ----------------------------------------------

(test-assert (init-error? (lambda () (d:make-random-port (open-input-bytevector (make-bytevector 10 5))))))  ; too few bytes
(test-assert (init-error? (lambda () (d:make-random-port (open-input-bytevector (make-bytevector 32 0))))))  ; all-zero seed
(test-assert (init-error? (lambda () (d:make-random-port 'not-a-port))))                                     ; bad initializer
(test-assert (init-error? (lambda () (d:make-random-port #u8(1 2 3)))))                                      ; not a state or port

;; other objects — including ordinary R7RS error objects — are not
;; random-port-initialization-errors
(test-assert (not (d:random-port-initialization-error? 'nope)))
(test-assert (not (d:random-port-initialization-error?
                   (guard (e (#t e)) (error "unrelated")))))

(let ((runner (test-runner-current)))
  (test-end "srfi-271")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
