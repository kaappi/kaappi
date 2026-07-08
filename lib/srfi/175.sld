(define-library (srfi 175)
  (import (scheme base))
  (export ascii-codepoint?
          ascii-bytevector?
          ascii-char? ascii-string?
          ascii-control? ascii-non-control?
          ascii-space-or-tab? ascii-other-graphic?
          ascii-alphanumeric? ascii-alphabetic?
          ascii-numeric? ascii-whitespace?
          ascii-upper-case? ascii-lower-case?
          ascii-ci=? ascii-ci<? ascii-ci>? ascii-ci<=? ascii-ci>=?
          ascii-string-ci=? ascii-string-ci<? ascii-string-ci>?
          ascii-string-ci<=? ascii-string-ci>=?
          ascii-upcase ascii-downcase
          ascii-control->graphic ascii-graphic->control
          ascii-mirror-bracket
          ascii-digit-value ascii-upper-case-value ascii-lower-case-value
          ascii-nth-digit ascii-nth-upper-case ascii-nth-lower-case)
  (begin
    ;; Predicates: ASCII vs non-ASCII
    (define (ascii-codepoint? x) (and (integer? x) (exact? x) (<= 0 x 127)))
    (define (ascii-bytevector? obj)
      (and (bytevector? obj)
           (let loop ((i 0))
             (or (= i (bytevector-length obj))
                 (and (<= (bytevector-u8-ref obj i) 127)
                      (loop (+ i 1)))))))
    (define (ascii-char? c) (and (char? c) (<= (char->integer c) 127)))
    (define (ascii-string? s)
      (and (string? s)
           (let loop ((i 0))
             (or (= i (string-length s))
                 (and (ascii-char? (string-ref s i)) (loop (+ i 1)))))))

    ;; Predicates: subsets of ASCII
    (define (ascii-control? c)
      (let ((n (if (char? c) (char->integer c) c)))
        (or (<= 0 n 31) (= n 127))))
    (define (ascii-non-control? c)
      (let ((n (if (char? c) (char->integer c) c)))
        (<= 32 n 126)))
    (define (ascii-space-or-tab? c)
      (let ((n (if (char? c) (char->integer c) c)))
        (or (= n 32) (= n 9))))
    (define (ascii-other-graphic? c)
      (let ((n (if (char? c) (char->integer c) c)))
        (or (<= 33 n 47) (<= 58 n 64) (<= 91 n 96) (<= 123 n 126))))
    (define (ascii-alphanumeric? c)
      (or (ascii-alphabetic? c) (ascii-numeric? c)))
    (define (ascii-alphabetic? c)
      (or (ascii-upper-case? c) (ascii-lower-case? c)))
    (define (ascii-numeric? c)
      (let ((n (if (char? c) (char->integer c) c)))
        (<= 48 n 57)))
    (define (ascii-whitespace? c)
      (let ((n (if (char? c) (char->integer c) c)))
        (or (= n 32) (<= 9 n 13))))
    (define (ascii-upper-case? c)
      (let ((n (if (char? c) (char->integer c) c)))
        (<= 65 n 90)))
    (define (ascii-lower-case? c)
      (let ((n (if (char? c) (char->integer c) c)))
        (<= 97 n 122)))

    ;; Case-insensitive character comparison
    (define (%ci-fold c)
      (let ((n (if (char? c) (char->integer c) c)))
        (if (<= 65 n 90) (+ n 32) n)))
    (define (ascii-ci=? c1 c2) (= (%ci-fold c1) (%ci-fold c2)))
    (define (ascii-ci<? c1 c2) (< (%ci-fold c1) (%ci-fold c2)))
    (define (ascii-ci>? c1 c2) (> (%ci-fold c1) (%ci-fold c2)))
    (define (ascii-ci<=? c1 c2) (<= (%ci-fold c1) (%ci-fold c2)))
    (define (ascii-ci>=? c1 c2) (>= (%ci-fold c1) (%ci-fold c2)))

    ;; Case-insensitive string comparison
    (define (%string-ci-cmp s1 s2)
      (let ((len1 (string-length s1)) (len2 (string-length s2)))
        (let loop ((i 0))
          (cond ((and (= i len1) (= i len2)) 0)
                ((= i len1) -1)
                ((= i len2)  1)
                (else
                 (let ((a (%ci-fold (string-ref s1 i)))
                       (b (%ci-fold (string-ref s2 i))))
                   (cond ((< a b) -1)
                         ((> a b)  1)
                         (else (loop (+ i 1))))))))))
    (define (ascii-string-ci=?  s1 s2) (= (%string-ci-cmp s1 s2) 0))
    (define (ascii-string-ci<?  s1 s2) (< (%string-ci-cmp s1 s2) 0))
    (define (ascii-string-ci>?  s1 s2) (> (%string-ci-cmp s1 s2) 0))
    (define (ascii-string-ci<=? s1 s2) (<= (%string-ci-cmp s1 s2) 0))
    (define (ascii-string-ci>=? s1 s2) (>= (%string-ci-cmp s1 s2) 0))

    ;; Case conversion
    (define (ascii-upcase c)
      (if (char? c)
          (if (ascii-lower-case? c)
              (integer->char (- (char->integer c) 32)) c)
          (if (ascii-lower-case? c) (- c 32) c)))
    (define (ascii-downcase c)
      (if (char? c)
          (if (ascii-upper-case? c)
              (integer->char (+ (char->integer c) 32)) c)
          (if (ascii-upper-case? c) (+ c 32) c)))

    ;; Control <-> graphic conversion
    (define (ascii-control->graphic c)
      (let ((n (if (char? c) (char->integer c) c)))
        (cond ((<= 0 n 31)
               (let ((g (+ n 64)))
                 (if (char? c) (integer->char g) g)))
              ((= n 127)
               (if (char? c) #\? 63))
              (else #f))))
    (define (ascii-graphic->control c)
      (let ((n (if (char? c) (char->integer c) c)))
        (cond ((= n 63)
               (if (char? c) (integer->char 127) 127))
              ((<= 64 n 95)
               (let ((ctrl (- n 64)))
                 (if (char? c) (integer->char ctrl) ctrl)))
              (else #f))))

    ;; Bracket mirroring
    (define (ascii-mirror-bracket c)
      (let ((n (if (char? c) (char->integer c) c)))
        (let ((mirror (cond ((= n 40) 41)   ; ( -> )
                            ((= n 41) 40)   ; ) -> (
                            ((= n 91) 93)   ; [ -> ]
                            ((= n 93) 91)   ; ] -> [
                            ((= n 123) 125) ; { -> }
                            ((= n 125) 123) ; } -> {
                            ((= n 60) 62)   ; < -> >
                            ((= n 62) 60)   ; > -> <
                            (else #f))))
          (if mirror
              (if (char? c) (integer->char mirror) mirror)
              #f))))

    ;; Digit/letter value extraction
    (define (ascii-digit-value c limit)
      (let ((n (if (char? c) (char->integer c) c)))
        (if (<= 48 n 57)
            (let ((v (- n 48)))
              (if (< v limit) v #f))
            #f)))
    (define (ascii-upper-case-value c offset limit)
      (if (ascii-upper-case? c)
          (let ((v (- (if (char? c) (char->integer c) c) 65)))
            (if (< v limit) (+ v offset) #f))
          #f))
    (define (ascii-lower-case-value c offset limit)
      (if (ascii-lower-case? c)
          (let ((v (- (if (char? c) (char->integer c) c) 97)))
            (if (< v limit) (+ v offset) #f))
          #f))

    ;; Nth-element constructors
    (define (ascii-nth-digit n)
      (if (and (exact-integer? n) (<= 0 n 9))
          (integer->char (+ n 48))
          #f))
    (define (ascii-nth-upper-case n)
      (integer->char (+ (modulo n 26) 65)))
    (define (ascii-nth-lower-case n)
      (integer->char (+ (modulo n 26) 97)))))
