;; SRFI-277 (cyclic ports) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi277.scm

(import (scheme base)
        (scheme read)
        (scheme write)
        (scheme char)
        (srfi 64)
        (srfi 277)
        (srfi 271 determinized))

(test-begin "srfi-277")

;; #t iff calling thunk raises an ordinary error object.
(define (error-raised? thunk)
  (guard (e ((error-object? e) #t) (#t #f))
    (thunk)
    #f))

;;; --- the two spec examples verbatim -------------------------------------

(test-equal "spec example: read-bytevector cycles a bytevector"
  #u8(1 2 3 4 1 2)
  (let ((p (open-cyclic-input-bytevector #u8(1 2 3 4))))
    (read-bytevector 6 p)))

(test-equal "spec example: read-string cycles a string"
  "frobfrob"
  (let ((p (open-cyclic-input-string "frob")))
    (read-string 8 p)))

;;; --- reads across several cycles ----------------------------------------

(test-equal "read-u8 wraps repeatedly in order"
  '(1 2 3 1 2 3 1)
  (let ((p (open-cyclic-input-bytevector #u8(1 2 3))))
    (let loop ((i 0) (acc '()))
      (if (= i 7) (reverse acc) (loop (+ i 1) (cons (read-u8 p) acc))))))

(test-equal "read-string length need not be a multiple of the cycle"
  "abababa"
  (let ((p (open-cyclic-input-string "ab")))
    (read-string 7 p)))

(test-equal "one-element cycle is a portable /dev/zero"
  #u8(0 0 0 0)
  (let ((p (open-cyclic-input-bytevector #u8(0))))
    (read-bytevector 4 p)))

;;; --- ports are ordinary ports -------------------------------------------

(let ((p (open-cyclic-input-string "x")))
  (test-assert "cyclic port is a port" (port? p))
  (test-assert "cyclic string port is an input port" (input-port? p))
  (test-assert "cyclic string port is textual" (textual-port? p))
  (test-assert "cyclic string port is not binary" (not (binary-port? p)))
  (test-assert "cyclic port is open when created" (input-port-open? p)))

(let ((p (open-cyclic-input-bytevector #u8(1))))
  (test-assert "cyclic bytevector port is an input port" (input-port? p))
  (test-assert "cyclic bytevector port is binary" (binary-port? p))
  (test-assert "cyclic bytevector port is not textual" (not (textual-port? p))))

(test-assert "call-with-port closes the cyclic port afterwards"
  (let ((p (open-cyclic-input-string "x")))
    (call-with-port p (lambda (port) (read-char port)))
    (not (input-port-open? p))))

;;; --- reading never produces EOF ------------------------------------------

(test-assert "a long read never yields the eof object"
  (let ((p (open-cyclic-input-bytevector #u8(1 2 3))))
    (let loop ((i 0))
      (or (= i 100)
          (and (not (eof-object? (read-u8 p)))
               (loop (+ i 1)))))))

(test-assert "char-ready? is #t on a cyclic port"
  (char-ready? (open-cyclic-input-string "x")))

(test-assert "u8-ready? is #t on a cyclic port"
  (u8-ready? (open-cyclic-input-bytevector #u8(1))))

(test-equal "read-bytevector! fills the whole target"
  '(1 2 3 1 2)
  (let* ((p (open-cyclic-input-bytevector #u8(1 2 3)))
         (bv (make-bytevector 5)))
    (read-bytevector! bv p)
    (let loop ((i 0) (acc '()))
      (if (= i 5) (reverse acc)
          (loop (+ i 1) (cons (bytevector-u8-ref bv i) acc))))))

(test-equal "peek-char returns a character, never eof"
  #\x
  (let ((p (open-cyclic-input-string "x")))
    (peek-char p)))

;;; --- textual details ------------------------------------------------------

(test-equal "multi-byte characters wrap cleanly under read-char"
  "λμλμλ"
  (let ((p (open-cyclic-input-string "λμ")))
    (let loop ((i 0) (acc '()))
      (if (= i 5) (list->string (reverse acc))
          (loop (+ i 1) (cons (read-char p) acc))))))

(test-equal "peek-char then read-char across the wrap point"
  (list #\a #\a #\λ #\λ)
  (let ((p (open-cyclic-input-string "aλμ")))
    (read-char p)                       ; a
    (read-char p)                       ; λ
    (read-char p)                       ; μ (cursor wraps to a)
    (list (peek-char p) (read-char p) (peek-char p) (read-char p))))

(test-equal "read-line returns the same line forever when the cycle has a newline"
  '("ab" "ab" "ab")
  (let ((p (open-cyclic-input-string "ab\n")))
    (list (read-line p) (read-line p) (read-line p))))

(test-equal "read parses successive datums from a cyclic port"
  '((a) b)
  (let ((p (open-cyclic-input-string "(a)b")))
    (list (read p) (read p))))

;; Large enough that the one-byte-per-reparse form of the refill loop (fixed
;; to a 4096-byte burst) would take seconds under the Debug CI leg; not timed.
(test-equal "read of a multi-kilobyte datum from a cyclic port"
  4001
  (let* ((big (let loop ((i 0) (acc '()))
                (if (= i 4000)
                    (cons 'config (reverse acc))
                    (loop (+ i 1) (cons i acc)))))
         (out (open-output-string)))
    (write big out)
    (let ((p (open-cyclic-input-string (get-output-string out))))
      (length (read p)))))

;;; --- positioning (SRFI 192) ----------------------------------------------

(test-assert "port-has-port-position? is #t"
  (port-has-port-position? (open-cyclic-input-bytevector #u8(1))))

(test-assert "port-has-set-port-position!? is #t"
  (port-has-set-port-position!? (open-cyclic-input-bytevector #u8(1))))

(let ((p (open-cyclic-input-bytevector #u8(1 2 3))))
  (read-bytevector 13 p)                ; 4 cycles + 1
  (test-equal "port-position counts bytes, not cycles" 13 (port-position p))
  (let ((five (read-bytevector 5 p)))
    (set-port-position! p 13)
    (test-equal "the SRFI's own re-read test: seek back, read the same 5"
      #t (equal? five (read-bytevector 5 p)))))

(test-equal "set-port-position! accepts any non-negative position"
  '(#\b #\a)
  (let ((p (open-cyclic-input-string "ab")))
    (set-port-position! p 5)            ; 5 mod 2 = 1: continues at 'b'
    (list (read-char p) (read-char p))))

(test-equal "set-port-position! to 0 rewinds to the start"
  "ab"
  (let ((p (open-cyclic-input-string "ab")))
    (read-char p)
    (set-port-position! p 0)
    (read-string 2 p)))

;;; --- errors ----------------------------------------------------------------

(test-assert "open-cyclic-input-string signals an error on an empty string"
  (error-raised? (lambda () (open-cyclic-input-string ""))))

(test-assert "open-cyclic-input-bytevector signals an error on an empty bytevector"
  (error-raised? (lambda () (open-cyclic-input-bytevector #u8()))))

(test-assert "open-cyclic-input-string signals an error on a non-string"
  (error-raised? (lambda () (open-cyclic-input-string 42))))

(test-assert "open-cyclic-input-bytevector signals an error on a non-bytevector"
  (error-raised? (lambda () (open-cyclic-input-bytevector 'x))))

(test-assert "reading a closed cyclic port errors instead of cycling"
  (let ((p (open-cyclic-input-string "x")))
    (close-port p)
    (error-raised? (lambda () (read-char p)))))

;;; --- the source is snapshotted (documented extension) ---------------------

(test-equal "mutating the source string after the call does not affect the port"
  "abab"
  (let* ((s (string-copy "ab"))
         (p (open-cyclic-input-string s)))
    (string-set! s 0 #\!)
    (read-string 4 p)))

(test-equal "mutating the source bytevector after the call does not affect the port"
  #u8(1 1 1 1)
  (let* ((bv (make-bytevector 2 1))
         (p (open-cyclic-input-bytevector bv)))
    (bytevector-u8-set! bv 0 9)
    (bytevector-u8-set! bv 1 2)
    (read-bytevector 4 p)))

;;; --- SRFI 271 integration --------------------------------------------------

(test-assert "a short cyclic bytevector satisfies make-random-port's 32-byte seed read"
  (let ((p (make-random-port (open-cyclic-input-bytevector #u8(1 2 3)))))
    (and (port? p) (input-port? p))))

(test-equal "equal cyclic seeds yield identical random-port streams"
  #t
  (let* ((a (make-random-port (open-cyclic-input-bytevector #u8(1 2 3))))
         (b (make-random-port (open-cyclic-input-bytevector #u8(1 2 3)))))
    (equal? (read-bytevector 64 a) (read-bytevector 64 b))))

;;; --- cond-expand integration ----------------------------------------------

(test-equal "srfi-277 is a cond-expand feature identifier"
  'yes
  (cond-expand (srfi-277 'yes) (else 'no)))

(test-end "srfi-277")
