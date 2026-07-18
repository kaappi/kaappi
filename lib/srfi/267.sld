;; SRFI 267: Raw String Syntax
;;
;; Raw strings are a lexical syntax for strings that do not interpret escape
;; sequences, useful when the data contains many `\` or `"` characters that
;; would otherwise need escaping. The lexical form itself
;;
;;     #" X " ...content... " X "
;;
;; (where X is a delimiter containing no `"`) is recognised natively by the
;; Kaappi reader. This library provides the port-level procedures for reading
;; and writing raw strings, plus the delimiter helpers.
;;
;; Note: the SRFI text names the port defaults `(default-input-port)` and
;; `(default-output-port)`; Kaappi uses their R7RS equivalents
;; `(current-input-port)` and `(current-output-port)`.

(define-library (srfi 267)
  (import (scheme base))
  (export read-raw-string
          read-raw-string-after-prefix
          can-delimit?
          generate-delimiter
          write-raw-string
          raw-string-read-error?
          raw-string-write-error?)
  (begin

    ;; Condition objects raised on failure. Only the predicates are exported;
    ;; the message is retained for use from a `guard` clause.
    (define-record-type <raw-string-read-error>
      (make-read-error message)
      raw-string-read-error?
      (message raw-string-read-error-message))

    (define-record-type <raw-string-write-error>
      (make-write-error message)
      raw-string-write-error?
      (message raw-string-write-error-message))

    ;; --- string helpers (kept internal so the library needs only scheme base)

    ;; Do the `nn` chars of `needle` equal the chars of `s` starting at `i`?
    (define (substring-at? s i needle nn)
      (let loop ((k 0))
        (cond ((= k nn) #t)
              ((char=? (string-ref s (+ i k)) (string-ref needle k))
               (loop (+ k 1)))
              (else #f))))

    ;; Does `haystack` contain `needle` as a contiguous substring?
    (define (string-contains? haystack needle)
      (let ((hn (string-length haystack))
            (nn (string-length needle)))
        (let loop ((i 0))
          (cond ((> (+ i nn) hn) #f)
                ((substring-at? haystack i needle nn) #t)
                (else (loop (+ i 1)))))))

    ;; Does `s` end with `suffix`?
    (define (string-ends-with? s suffix)
      (let ((sn (string-length s)) (fn (string-length suffix)))
        (and (>= sn fn)
             (substring-at? s (- sn fn) suffix fn))))

    ;; Does `s` contain the character `ch`?
    (define (string-has-char? s ch)
      (let ((n (string-length s)))
        (let loop ((i 0))
          (cond ((= i n) #f)
                ((char=? (string-ref s i) ch) #t)
                (else (loop (+ i 1)))))))

    ;; Length of the longest run of `ch` in `s`.
    (define (longest-run s ch)
      (let ((n (string-length s)))
        (let loop ((i 0) (cur 0) (best 0))
          (if (= i n)
              (max cur best)
              (if (char=? (string-ref s i) ch)
                  (loop (+ i 1) (+ cur 1) best)
                  (loop (+ i 1) 0 (max cur best)))))))

    ;; --- delimiter predicates -------------------------------------------

    ;; True iff string2 is a ⟨valid delimiter⟩ and string1 is a valid
    ;; ⟨raw string internal (string2)⟩ — i.e. string2 has no `"`, string1 does
    ;; not contain `"` string2 `"`, and string1 does not end with `"` string2.
    (define (can-delimit? string1 string2)
      (and (not (string-has-char? string2 #\"))
           (not (string-contains? string1
                                  (string-append "\"" string2 "\"")))
           (not (string-ends-with? string1
                                   (string-append "\"" string2)))))

    ;; Return a delimiter D such that (can-delimit? string D). The empty
    ;; delimiter works whenever `string` has no `""` and does not end with `"`;
    ;; otherwise a run of `=` longer than any run of `=` in `string` is valid,
    ;; because that run then never occurs in `string` at all, so neither
    ;; `"=...="` nor a trailing `"=...=` can appear. Linear time.
    (define (generate-delimiter string)
      (if (can-delimit? string "")
          ""
          (make-string (+ 1 (longest-run string #\=)) #\=)))

    ;; --- reading --------------------------------------------------------

    (define (read-raw-string . opt)
      (let ((port (if (pair? opt) (car opt) (current-input-port))))
        (if (and (eqv? (read-char port) #\#)
                 (eqv? (read-char port) #\"))
            (read-after-prefix port)
            (raise (make-read-error "read-raw-string: expected #\" prefix")))))

    (define (read-raw-string-after-prefix . opt)
      (read-after-prefix
       (if (pair? opt) (car opt) (current-input-port))))

    ;; Assumes the `#"` prefix has been consumed. Reads the delimiter, then the
    ;; content up to the terminating `" X "`.
    (define (read-after-prefix port)
      (read-content port (read-delimiter port)))

    ;; The delimiter X runs up to (and consumes) the first `"`.
    (define (read-delimiter port)
      (let loop ((acc '()))
        (let ((c (read-char port)))
          (cond ((eof-object? c)
                 (raise (make-read-error "raw string: eof while reading delimiter")))
                ((char=? c #\") (list->string (reverse acc)))
                (else (loop (cons c acc)))))))

    ;; Read content until the leftmost terminator `" delim "`. `buf` holds the
    ;; content read so far in reverse; when its most recent `tn` chars match the
    ;; terminator we stop and drop them.
    (define (read-content port delim)
      (let* ((rterm (reverse (string->list
                              (string-append "\"" delim "\""))))
             (tn (length rterm)))
        (let loop ((buf '()) (blen 0))
          (let ((c (read-char port)))
            (if (eof-object? c)
                (raise (make-read-error "raw string: eof before terminator"))
                (let ((buf2 (cons c buf)) (blen2 (+ blen 1)))
                  (if (and (>= blen2 tn) (prefix-equal? buf2 rterm))
                      (list->string (reverse (list-tail buf2 tn)))
                      (loop buf2 blen2))))))))

    ;; Do the first (length pat) chars of lst equal pat, in order?
    (define (prefix-equal? lst pat)
      (cond ((null? pat) #t)
            ((null? lst) #f)
            ((char=? (car lst) (car pat)) (prefix-equal? (cdr lst) (cdr pat)))
            (else #f)))

    ;; --- writing --------------------------------------------------------

    (define (write-raw-string string1 string2 . opt)
      (if (can-delimit? string1 string2)
          (write-string
           (string-append "#\"" string2 "\"" string1 "\"" string2 "\"")
           (if (pair? opt) (car opt) (current-output-port)))
          (raise (make-write-error
                  "write-raw-string: delimiter cannot represent the string"))))))
