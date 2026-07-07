;; Audit tests for src/primitives_bytevector.zig — R7RS 6.9 bytevectors,
;; 6.13.3 binary I/O, and bytevector ports.
;; Audit campaign Phase 2.10 (#1137). Complements r7rs-tests.scm §6.9.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write))
(import (chibi test))

(test-begin "primitives_bytevector audit")

;;; --- bytevector? ---
(test #t (bytevector? #u8()))
(test #t (bytevector? (bytevector 1 2)))
(test #f (bytevector? #(1 2)))
(test #f (bytevector? "ab"))
(test #f (bytevector? 7))

;;; --- make-bytevector ---
(test #u8(12 12) (make-bytevector 2 12))
(test 3 (bytevector-length (make-bytevector 3)))
(test #u8() (make-bytevector 0))
(test #u8(0 0) (make-bytevector 2 0))
(test #u8(255) (make-bytevector 1 255))
(test 'caught (guard (e (#t 'caught)) (make-bytevector -1)))
(test 'caught (guard (e (#t 'caught)) (make-bytevector 2 256)))
(test 'caught (guard (e (#t 'caught)) (make-bytevector 2 -1)))
(test 'caught (guard (e (#t 'caught)) (make-bytevector 2 1.5)))
(test 'caught (guard (e (#t 'caught)) (make-bytevector 2.0)))

;;; --- bytevector ---
(test #u8(1 3 5 1 3 5) (bytevector 1 3 5 1 3 5))
(test #u8() (bytevector))
(test #u8(0 255) (bytevector 0 255))
(test 'caught (guard (e (#t 'caught)) (bytevector 256)))
(test 'caught (guard (e (#t 'caught)) (bytevector -1)))
(test 'caught (guard (e (#t 'caught)) (bytevector 1.5)))
(test 'caught (guard (e (#t 'caught)) (bytevector "a")))

;;; --- bytevector-length ---
(test 0 (bytevector-length #u8()))
(test 8 (bytevector-length #u8(1 1 2 3 5 8 13 21)))
(test 'caught (guard (e (#t 'caught)) (bytevector-length "ab")))

;;; --- bytevector-u8-ref ---
;; R7RS 6.9 example
(test 8 (bytevector-u8-ref #u8(1 1 2 3 5 8 13 21) 5))
(test 1 (bytevector-u8-ref #u8(1 2 3) 0))
(test 3 (bytevector-u8-ref #u8(1 2 3) 2))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-ref #u8(1 2 3) 3)))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-ref #u8(1 2 3) -1)))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-ref #u8(1 2 3) 1.0)))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-ref #u8(1 2 3) (expt 2 100))))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-ref #u8() 0)))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-ref '(1 2) 0)))

;;; --- bytevector-u8-set! ---
;; R7RS 6.9 example
(test #u8(1 3 3 4)
    (let ((bv (bytevector 1 2 3 4)))
      (bytevector-u8-set! bv 1 3)
      bv))
(test #u8(255) (let ((bv (make-bytevector 1 0))) (bytevector-u8-set! bv 0 255) bv))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-set! (bytevector 1 2) 2 0)))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-set! (bytevector 1 2) -1 0)))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-set! (bytevector 1 2) 0 256)))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-set! (bytevector 1 2) 0 -1)))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-set! (bytevector 1 2) 0 1.5)))
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-set! "ab" 0 65)))
;; R7RS 6.9: literal bytevectors are immutable.
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-set! #u8(0 1 2) 1 99)))

;;; --- bytevector-copy ---
;; R7RS 6.9 example
(test #u8(3 4) (bytevector-copy #u8(1 2 3 4 5) 2 4))
(test #u8(1 2 3) (bytevector-copy #u8(1 2 3)))
(test #u8(3) (bytevector-copy #u8(1 2 3) 2))
(test #u8() (bytevector-copy #u8(1 2) 1 1))
(test #f (let ((a (bytevector 1 2))) (eq? a (bytevector-copy a))))
(test 'caught (guard (e (#t 'caught)) (bytevector-copy #u8(1 2) 2 1)))
(test 'caught (guard (e (#t 'caught)) (bytevector-copy #u8(1 2) 0 3)))
(test 'caught (guard (e (#t 'caught)) (bytevector-copy #u8(1 2) -1)))
(test 'caught (guard (e (#t 'caught)) (bytevector-copy '(1 2))))

;;; --- bytevector-copy! ---
;; R7RS 6.9 example
(test #u8(10 1 2 40 50)
    (let ((a (bytevector 1 2 3 4 5))
          (b (bytevector 10 20 30 40 50)))
      (bytevector-copy! b 1 a 0 2)
      b))
;; overlapping copy within one bytevector, both directions
(test #u8(2 3 4 5 5)
    (let ((v (bytevector 1 2 3 4 5))) (bytevector-copy! v 0 v 1 5) v))
(test #u8(1 1 2 3 4)
    (let ((v (bytevector 1 2 3 4 5))) (bytevector-copy! v 1 v 0 4) v))
;; at == (bytevector-length to) with empty source range is allowed
(test #u8(1 2)
    (let ((v (bytevector 1 2))) (bytevector-copy! v 2 #u8()) v))
(test 'caught (guard (e (#t 'caught)) (bytevector-copy! (bytevector 1 2) 1 #u8(9 9))))
(test 'caught (guard (e (#t 'caught)) (bytevector-copy! (bytevector 1 2) -1 #u8(9))))
(test 'caught (guard (e (#t 'caught)) (bytevector-copy! (bytevector 1 2) 0 #u8(9 9 9) 1 4)))
(test 'caught (guard (e (#t 'caught)) (bytevector-copy! '(1 2) 0 #u8(9))))
(test 'caught (guard (e (#t 'caught)) (bytevector-copy! (bytevector 1 2) 0 '(9))))

;;; --- bytevector-append ---
;; R7RS 6.9 example
(test #u8(0 1 2 3 4 5) (bytevector-append #u8(0 1 2) #u8(3 4 5)))
(test #u8() (bytevector-append))
(test #u8(1) (bytevector-append #u8() #u8(1) #u8()))
(test 'caught (guard (e (#t 'caught)) (bytevector-append #u8(1) '(2))))

;;; --- utf8->string ---
;; R7RS 6.9 example
(test "A" (utf8->string #u8(#x41)))
(test "λ" (utf8->string #u8(#xCE #xBB)))
(test "" (utf8->string #u8()))
;; start/end are BYTE indices
(test "λ" (utf8->string #u8(#x41 #xCE #xBB) 1))
(test "A" (utf8->string #u8(#x41 #xCE #xBB) 0 1))
(test 'caught (guard (e (#t 'caught)) (utf8->string #u8(1 2) 0 3)))
(test 'caught (guard (e (#t 'caught)) (utf8->string "abc")))
;; Invalid UTF-8 is accepted unchecked, creating a corrupt string: write shows
;; a replacement char and string-length answers, but string-ref on the same
;; string raises "expected valid UTF-8 string". Validate at construction.
;; FAIL: #1178 (utf8->string skips UTF-8 validation; corrupt string breaks string-ref)
;; (test 'caught (guard (e (#t 'caught)) (utf8->string (bytevector #xFF))))
;; (test 'caught (guard (e (#t 'caught)) (utf8->string (bytevector #xC0 #x80))))    ; overlong
;; (test 'caught (guard (e (#t 'caught)) (utf8->string (bytevector #xED #xA0 #x80)))) ; surrogate
;; (test #\A (string-ref (utf8->string (bytevector #xFF #x41)) 1))  ; works today, but index 0 raises

;;; --- string->utf8 ---
;; R7RS 6.9 example
(test #u8(#xCE #xBB) (string->utf8 "λ"))
(test #u8() (string->utf8 ""))
;; start/end are CODEPOINT indices
(test #u8(#xCE #xBB) (string->utf8 "aλb" 1 2))
(test #u8(#x62) (string->utf8 "aλb" 2 3))
(test 4 (bytevector-length (string->utf8 (string (integer->char #x1F600)))))
(test 'caught (guard (e (#t 'caught)) (string->utf8 "ab" 0 3)))
(test 'caught (guard (e (#t 'caught)) (string->utf8 #u8(65))))
;; round trips
(test "hello λ 😀" (utf8->string (string->utf8 "hello λ 😀")))
(test #u8(104 105) (string->utf8 (utf8->string #u8(104 105))))

;;; --- open-input-bytevector / read-u8 / peek-u8 ---
(test 10 (read-u8 (open-input-bytevector #u8(10))))
(test '(10 10 10 20 done)
    (let ((p (open-input-bytevector #u8(10 20))))
      (list (peek-u8 p) (peek-u8 p) (read-u8 p) (read-u8 p)
            (if (eof-object? (read-u8 p)) 'done 'not-eof))))
(test #t (eof-object? (read-u8 (open-input-bytevector #u8()))))
(test #t (eof-object? (peek-u8 (open-input-bytevector #u8()))))
;; default-port path: read-u8 with no argument uses current-input-port
(test 65 (parameterize ((current-input-port (open-input-bytevector #u8(65))))
           (read-u8)))
(test 'caught (guard (e (#t 'caught)) (read-u8 "not-a-port")))
(test 'caught (guard (e (#t 'caught)) (read-u8 (open-output-bytevector))))
(test 'caught (guard (e (#t 'caught))
                (let ((p (open-input-bytevector #u8(1))))
                  (close-port p)
                  (read-u8 p))))

;;; --- u8-ready? ---
(test #t (u8-ready? (open-input-bytevector #u8(1))))
(test #t (let ((p (open-input-bytevector #u8(1 2))))
           (peek-u8 p)
           (u8-ready? p)))
;; R7RS 6.13.3: "If the port is at end of file then u8-ready? returns #t"
(test #t (u8-ready? (open-input-bytevector #u8())))
(test #t (let ((p (open-input-bytevector #u8(7)))) (read-u8 p) (u8-ready? p)))

;;; --- write-u8 / open-output-bytevector / get-output-bytevector ---
(test #u8(1 2 3)
    (let ((p (open-output-bytevector)))
      (write-u8 1 p)
      (write-bytevector #u8(2 3) p)
      (get-output-bytevector p)))
(test #u8() (get-output-bytevector (open-output-bytevector)))
(test #u8(0 255)
    (let ((p (open-output-bytevector)))
      (write-u8 0 p) (write-u8 255 p)
      (get-output-bytevector p)))
(test 'caught (guard (e (#t 'caught)) (write-u8 256 (open-output-bytevector))))
(test 'caught (guard (e (#t 'caught)) (write-u8 -1 (open-output-bytevector))))
(test 'caught (guard (e (#t 'caught)) (write-u8 1.0 (open-output-bytevector))))
(test 'caught (guard (e (#t 'caught)) (write-u8 65 (open-input-bytevector #u8()))))
(test 'caught (guard (e (#t 'caught)) (get-output-bytevector (open-output-string))))
(test 'caught (guard (e (#t 'caught)) (get-output-bytevector 42)))

;;; --- read-bytevector ---
(test #u8(1 2 3) (read-bytevector 3 (open-input-bytevector #u8(1 2 3 4))))
;; fewer than k available: returns what's there
(test #u8(1 2 3) (read-bytevector 5 (open-input-bytevector #u8(1 2 3))))
(test #t (eof-object? (read-bytevector 5 (open-input-bytevector #u8()))))
(test #u8() (read-bytevector 0 (open-input-bytevector #u8())))
(test 'caught (guard (e (#t 'caught)) (read-bytevector -1 (open-input-bytevector #u8()))))
(test 'caught (guard (e (#t 'caught)) (read-bytevector 1.5 (open-input-bytevector #u8()))))
;; peeked byte is consumed first
(test #u8(9 8)
    (let ((p (open-input-bytevector #u8(9 8))))
      (peek-u8 p)
      (read-bytevector 2 p)))

;;; --- read-bytevector! ---
(test '(2 #u8(9 1 2 9 9 9))
    (let ((bv (make-bytevector 6 9)))
      (let ((n (read-bytevector! bv (open-input-bytevector #u8(1 2)) 1 5)))
        (list n bv))))
(test '(3 #u8(1 2 3))
    (let ((bv (make-bytevector 3 0)))
      (let ((n (read-bytevector! bv (open-input-bytevector #u8(1 2 3 4)))))
        (list n bv))))
(test #t (eof-object? (read-bytevector! (make-bytevector 3)
                                        (open-input-bytevector #u8()))))
(test 0 (read-bytevector! (make-bytevector 3)
                          (open-input-bytevector #u8(1)) 2 2))
(test 'caught (guard (e (#t 'caught))
                (read-bytevector! (make-bytevector 2)
                                  (open-input-bytevector #u8(1)) 1 3)))
(test 'caught (guard (e (#t 'caught)) (read-bytevector! "ab" (open-input-bytevector #u8()))))

;;; --- write-bytevector ranges ---
(test #u8(2 3)
    (let ((p (open-output-bytevector)))
      (write-bytevector #u8(1 2 3 4) p 1 3)
      (get-output-bytevector p)))
(test #u8(3 4)
    (let ((p (open-output-bytevector)))
      (write-bytevector #u8(1 2 3 4) p 2)
      (get-output-bytevector p)))
(test 'caught (guard (e (#t 'caught))
                (write-bytevector #u8(1 2) (open-output-bytevector) 1 3)))
(test 'caught (guard (e (#t 'caught)) (write-bytevector '(1 2) (open-output-bytevector))))

(test-end "primitives_bytevector audit")
