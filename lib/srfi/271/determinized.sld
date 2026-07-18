;; SRFI 271: Random port libraries — determinized variant.
;;
;; A determinized random port is a binary input port driven by a fully
;; deterministic algorithm (here xoshiro256**). Two determinized ports with
;; the same state produce the same sequence of bytes, which makes them
;; suitable for reproducible testing. The port's state can be captured,
;; compared, and used to construct a fresh port at that same state.
(define-library (srfi 271 determinized)
  (import (scheme base)
          (scheme case-lambda))
  (export make-random-port
          random-port?
          random-port-state
          random-port-state?
          random-port-state=?
          random-port-initialization-error?)
  (begin

    ;; Raised by make-random-port when an initializer cannot be used — an
    ;; invalid state object, or a port yielding too little / unsuitable data.
    (define-record-type <random-port-initialization-error>
      (make-random-port-initialization-error message irritant)
      random-port-initialization-error?
      (message random-port-initialization-error-message)
      (irritant random-port-initialization-error-irritant))

    ;; A random-port state is a self-describing bytevector produced by
    ;; %random-port-state: 46 bytes, "S271" magic, version 1, an out-position
    ;; in [0,8], the current output block, and the four state words. Because
    ;; it is a bytevector it round-trips through write/read verbatim as a
    ;; #u8(...) literal, satisfying SRFI 271's external-representation
    ;; invariance. An all-zero set of state words is the degenerate
    ;; xoshiro256** fixed point and is therefore not a valid state.
    (define (random-port-state? obj)
      (and (bytevector? obj)
           (= (bytevector-length obj) 46)
           (= (bytevector-u8-ref obj 0) 83)   ; #\S
           (= (bytevector-u8-ref obj 1) 50)   ; #\2
           (= (bytevector-u8-ref obj 2) 55)   ; #\7
           (= (bytevector-u8-ref obj 3) 49)   ; #\1
           (= (bytevector-u8-ref obj 4) 1)    ; version
           (<= (bytevector-u8-ref obj 5) 8)   ; out-position
           (state-words-nonzero? obj)))

    (define (state-words-nonzero? bv)
      (let loop ((i 14))
        (cond ((= i 46) #f)
              ((not (= (bytevector-u8-ref bv i) 0)) #t)
              (else (loop (+ i 1))))))

    ;; Equal states produce identical byte sequences; the snapshot is
    ;; canonical (the output block is a function of the state words), so
    ;; bytevector equality is exactly state equality.
    (define (random-port-state=? . states)
      (if (null? states)
          #t
          (let ((first (car states)))
            (let loop ((rest (cdr states)))
              (cond ((null? rest) #t)
                    ((equal? (car rest) first) (loop (cdr rest)))
                    (else #f))))))

    (define random-port-state %random-port-state)
    (define random-port? %random-port?)

    (define (bytevector-all-zero? bv)
      (let ((n (bytevector-length bv)))
        (let loop ((i 0))
          (cond ((= i n) #t)
                ((not (= (bytevector-u8-ref bv i) 0)) #f)
                (else (loop (+ i 1)))))))

    ;; Draw 32 seed bytes from a binary input port and build a determinized
    ;; port from them. Too few bytes, or an all-zero seed, is unusable.
    (define (seed-from-port port)
      (let ((seed (read-bytevector 32 port)))
        (cond
          ((or (eof-object? seed) (< (bytevector-length seed) 32))
           (raise (make-random-port-initialization-error
                   "make-random-port: insufficient random data from initializer"
                   port)))
          ((bytevector-all-zero? seed)
           (raise (make-random-port-initialization-error
                   "make-random-port: unsuitable (all-zero) random data from initializer"
                   port)))
          (else (%random-port-make-from-seed seed)))))

    ;; (make-random-port)            — randomly seeded from a randomized port
    ;; (make-random-port state)      — a port at exactly that state
    ;; (make-random-port binary-in)  — seeded from bytes read out of the port
    (define make-random-port
      (case-lambda
        (() (seed-from-port (%random-port-make-randomized)))
        ((initializer)
         (cond
           ((random-port-state? initializer)
            (%random-port-make-from-state initializer))
           ((and (input-port? initializer) (binary-port? initializer))
            (seed-from-port initializer))
           (else
            (raise (make-random-port-initialization-error
                    "make-random-port: initializer must be a random-port state or a binary input port"
                    initializer)))))))))
