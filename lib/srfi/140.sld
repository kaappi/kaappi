;;; SRFI 140 — Immutable Strings
;;;
;;; Kaappi has a single mutable string representation (no separate istring
;;; type with a guaranteed-O(1) contract), so istring? always answers #f —
;;; that keeps the required invariant "(string? x) is true whenever
;;; (istring? x) is true" trivially satisfied without overclaiming a
;;; guarantee Kaappi's engine cannot make. Everything else is implemented
;;; against Kaappi's native strings, reusing (srfi 13) and (srfi 152) for
;;; the large common surface.

(define-library (srfi 140)
  (import (except (scheme base) list->string string-map)
          (scheme char)
          (only (srfi 13)
                string-every string-any
                string-tabulate string-unfold string-unfold-right
                string-take string-drop string-take-right string-drop-right
                string-pad string-pad-right
                string-trim string-trim-right string-trim-both
                string-replace
                string-prefix? string-suffix?
                string-index string-index-right
                string-skip string-skip-right
                string-contains
                string-titlecase
                string-concatenate
                string-join
                string-count
                string-filter)
          (rename (only (srfi 13) string-delete) (string-delete string-remove))
          (only (srfi 152)
                string-null?
                reverse-list->string
                string-prefix-length string-suffix-length
                string-contains-right
                string-concatenate-reverse
                string-fold string-fold-right
                string-split)
          (rename (only (scheme base) list->string) (list->string %list->string)))

  (export
    ;; Predicates
    string? istring? string-null? string-every string-any
    ;; Constructors
    string string-tabulate string-unfold string-unfold-right
    ;; Conversion
    string->vector string->list vector->string list->string reverse-list->string
    string->utf8 utf8->string
    string->utf16 string->utf16be string->utf16le
    utf16->string utf16be->string utf16le->string
    ;; Selection
    string-length string-ref substring
    string-take string-drop string-take-right string-drop-right
    string-pad string-pad-right
    string-trim string-trim-right string-trim-both
    ;; Replacement
    string-replace
    ;; Comparison
    string=? string<? string>? string<=? string>=?
    string-ci=? string-ci<? string-ci>? string-ci<=? string-ci>=?
    ;; Prefixes and suffixes
    string-prefix-length string-suffix-length string-prefix? string-suffix?
    ;; Searching
    string-index string-index-right string-skip string-skip-right
    string-contains string-contains-right
    ;; Case conversion
    string-upcase string-downcase string-foldcase string-titlecase
    ;; Concatenation
    string-append string-concatenate string-concatenate-reverse string-join
    ;; Fold and map
    string-fold string-fold-right
    string-map string-for-each
    string-map-index string-for-each-index
    string-count string-filter string-remove
    ;; Replication and splitting
    string-repeat xsubstring string-split
    ;; Mutable string constructors
    make-string string-copy
    ;; Mutation
    string-set! string-fill! string-copy!)

  (begin

    (define (istring? obj) (and (string? obj) #f))

    (define (%opt-start args) (if (pair? args) (car args) 0))
    (define (%opt-end args default)
      (if (and (pair? args) (pair? (cdr args))) (cadr args) default))

    (define (%sublist lst start end)
      (let loop ((l lst) (i 0) (acc '()))
        (cond ((>= i end) (reverse acc))
              ((< i start) (loop (cdr l) (+ i 1) acc))
              (else (loop (cdr l) (+ i 1) (cons (car l) acc))))))

    (define (list->string lst . args)
      (%list->string (%sublist lst (%opt-start args) (%opt-end args (length lst)))))

    ;;; --- string-map / string-for-each-index / string-map-index ---
    ;;; string-map is a (documented) extension: proc may return a string
    ;;; as well as a character.

    (define (string-map proc s1 . ss)
      (let* ((strs (cons s1 ss))
             (len (apply min (map string-length strs))))
        (let loop ((i 0) (acc '()))
          (if (>= i len)
              (apply string-append (reverse acc))
              (let ((r (apply proc (map (lambda (s) (string-ref s i)) strs))))
                (loop (+ i 1) (cons (if (char? r) (string r) r) acc)))))))

    (define (string-for-each-index proc s . args)
      (let ((start (%opt-start args)) (end (%opt-end args (string-length s))))
        (let loop ((i start))
          (when (< i end)
            (proc i)
            (loop (+ i 1))))))

    (define (string-map-index proc s . args)
      (let ((start (%opt-start args)) (end (%opt-end args (string-length s))))
        (let loop ((i start) (acc '()))
          (if (>= i end)
              (apply string-append (reverse acc))
              (let ((r (proc i)))
                (loop (+ i 1) (cons (if (char? r) (string r) r) acc)))))))

    ;;; --- xsubstring / string-repeat ---

    (define (xsubstring s from . args)
      (let* ((to (if (pair? args) (car args) (string-length s)))
             (rest (if (pair? args) (cdr args) '()))
             (start (%opt-start rest))
             (end (%opt-end rest (string-length s)))
             (slen (- end start)))
        (cond
          ((> from to) (error "xsubstring: from > to" from to))
          ((= slen 0)
           (if (= from to) "" (error "xsubstring: empty range" s from to)))
          (else
           (let ((out (open-output-string)))
             (do ((i from (+ i 1)))
                 ((>= i to) (get-output-string out))
               (write-char (string-ref s (+ start (modulo i slen))) out)))))))

    (define (string-repeat s n)
      (let ((s (if (char? s) (string s) s)))
        (xsubstring s 0 (* n (string-length s)))))

    ;;; --- UTF-16 ---

    (define (%string->utf16 s start end endianness)
      (let* ((n (string-fold (lambda (c n)
                                (if (< (char->integer c) #x10000) (+ n 2) (+ n 4)))
                              0 s start end))
             (n (if endianness n (+ n 2)))
             (result (make-bytevector n 0))
             (hibits (if (eq? endianness 'little) 1 0))
             (lobits (- 1 hibits)))
        (when (not endianness)
          (bytevector-u8-set! result 0 #xfe)
          (bytevector-u8-set! result 1 #xff))
        (let loop ((i start) (j (if endianness 0 2)))
          (if (= i end)
              result
              (let ((cp (char->integer (string-ref s i))))
                (if (< cp #x10000)
                    (let* ((high (quotient cp 256)) (low (- cp (* 256 high))))
                      (bytevector-u8-set! result (+ j hibits) high)
                      (bytevector-u8-set! result (+ j lobits) low)
                      (loop (+ i 1) (+ j 2)))
                    (let* ((k (- cp #x10000))
                           (hs (+ #xd800 (quotient k 1024)))
                           (ls (+ #xdc00 (remainder k 1024)))
                           (h0 (quotient hs 256)) (l0 (- hs (* 256 h0)))
                           (h1 (quotient ls 256)) (l1 (- ls (* 256 h1))))
                      (bytevector-u8-set! result (+ j hibits) h0)
                      (bytevector-u8-set! result (+ j lobits) l0)
                      (bytevector-u8-set! result (+ j 2 hibits) h1)
                      (bytevector-u8-set! result (+ j 2 lobits) l1)
                      (loop (+ i 1) (+ j 4)))))))))

    (define (string->utf16 s . args)
      (%string->utf16 s (%opt-start args) (%opt-end args (string-length s)) #f))
    (define (string->utf16be s . args)
      (%string->utf16 s (%opt-start args) (%opt-end args (string-length s)) 'big))
    (define (string->utf16le s . args)
      (%string->utf16 s (%opt-start args) (%opt-end args (string-length s)) 'little))

    (define (%utf16->string bv start end endianness)
      (let* ((bom (and (not endianness)
                        (< start end)
                        (let ((b0 (bytevector-u8-ref bv start))
                              (b1 (bytevector-u8-ref bv (+ start 1))))
                          (cond ((and (= b0 #xfe) (= b1 #xff)) 'big)
                                ((and (= b1 #xfe) (= b0 #xff)) 'little)
                                (else #f)))))
             (start (if bom (+ start 2) start))
             (endianness (or endianness bom 'big))
             (hibits (if (eq? endianness 'big) 0 1))
             (lobits (- 1 hibits)))
        (let loop ((i start) (acc '()))
          (if (>= i end)
              (%list->string (reverse acc))
              (let* ((high (bytevector-u8-ref bv (+ i hibits)))
                     (low (bytevector-u8-ref bv (+ i lobits)))
                     (cp (+ (* 256 high) low)))
                (cond
                  ((< cp #xd800) (loop (+ i 2) (cons (integer->char cp) acc)))
                  ((and (< cp #xdc00) (< (+ i 2) end))
                   (let* ((i2 (+ i 2))
                          (high2 (bytevector-u8-ref bv (+ i2 hibits)))
                          (low2 (bytevector-u8-ref bv (+ i2 lobits)))
                          (cp2 (+ (* 256 high2) low2)))
                     (if (<= #xdc00 cp2 #xdfff)
                         (loop (+ i 4)
                               (cons (integer->char
                                       (+ #x10000 (* 1024 (- cp #xd800)) (- cp2 #xdc00)))
                                     acc))
                         (error "invalid UTF-16 surrogate pair" bv i))))
                  ((< cp #x10000) (loop (+ i 2) (cons (integer->char cp) acc)))
                  (else (error "invalid UTF-16" bv i))))))))

    (define (utf16->string bv . args)
      (%utf16->string bv (%opt-start args) (%opt-end args (bytevector-length bv)) #f))
    (define (utf16be->string bv . args)
      (%utf16->string bv (%opt-start args) (%opt-end args (bytevector-length bv)) 'big))
    (define (utf16le->string bv . args)
      (%utf16->string bv (%opt-start args) (%opt-end args (bytevector-length bv)) 'little))))
