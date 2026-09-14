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

    ;; Return a delimiter D such that (can-delimit? string D), computed in a
    ;; single pass over the character list. (Kaappi indexes strings by codepoint
    ;; — string-ref rescans UTF-8 from the front — so an indexed loop here would
    ;; be quadratic; a list walk is genuinely linear.) The empty delimiter works
    ;; whenever `string` has no `""` and does not end with `"`; otherwise a run
    ;; of `=` longer than any run of `=` in `string` is valid, because that run
    ;; then never occurs in `string` at all, so neither `"=...="` nor a trailing
    ;; `"=...=` can appear.
    (define (generate-delimiter string)
      (let loop ((chars (string->list string))
                 (prev #f)       ; previous character (#f before the first)
                 (best 0)        ; longest run of #\= seen so far
                 (run 0)         ; length of the current run of #\=
                 (adjacent #f))  ; has an adjacent `""` pair appeared?
        (if (null? chars)
            (if (and (not adjacent) (not (eqv? prev #\")))
                ""
                (make-string (+ 1 best) #\=))
            (let* ((c (car chars))
                   (run* (if (char=? c #\=) (+ run 1) 0)))
              (loop (cdr chars)
                    c
                    (if (> run* best) run* best)
                    run*
                    (or adjacent (and (eqv? prev #\") (char=? c #\"))))))))

    ;; --- reading --------------------------------------------------------

    ;; Resolve the single optional port argument, defaulting via (get-default).
    ;; The SRFI signatures take a fixed [port]; reject 2+ arguments with an arity
    ;; error rather than silently using the first and dropping the rest.
    (define (opt-port opt get-default)
      (cond ((null? opt) (get-default))
            ((null? (cdr opt)) (car opt))
            (else (error "srfi 267: at most one port argument expected"))))

    (define (read-raw-string . opt)
      (let ((port (opt-port opt current-input-port)))
        (if (and (eqv? (read-char port) #\#)
                 (eqv? (read-char port) #\"))
            (read-after-prefix port)
            (raise (make-read-error "read-raw-string: expected #\" prefix")))))

    (define (read-raw-string-after-prefix . opt)
      (read-after-prefix (opt-port opt current-input-port)))

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
      (let ((port (opt-port opt current-output-port)))
        (if (can-delimit? string1 string2)
            (write-string
             (string-append "#\"" string2 "\"" string1 "\"" string2 "\"")
             port)
            (raise (make-write-error
                    "write-raw-string: delimiter cannot represent the string")))))))
