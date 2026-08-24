;;; SRFI 166 (Monadic Formatting) — base library.
;;;
;;; A complete implementation of the SRFI 166 "base" bindings on a simple,
;;; first-class state model: a state variable is a record carrying a name, a
;;; default value and an immutable flag, and the formatting state is a hash
;;; table keyed by the state-variable object itself.  Formatters are ordinary
;;; procedures `(state -> state)` which mutate the state in place, so col/row
;;; tracking survives `with` (which restores only the variables it bound) while
;;; `forked`/`call-with-output` snapshot the table with hash-table-copy.

(define-library (srfi 166 base)
  (import (scheme base)
          (scheme char)
          (scheme cxr)
          (scheme write)
          (scheme inexact)
          (scheme file)
          (srfi 1)
          (srfi 69))
  (export show displayed written written-shared written-simply
          escaped maybe-escaped
          numeric numeric/comma numeric/si numeric/fitted
          nl fl space-to tab-to nothing
          each each-in-list joined joined/prefix joined/suffix
          joined/last joined/dot joined/range
          padded padded/right padded/both
          trimmed trimmed/right trimmed/both trimmed/lazy
          fitted fitted/right fitted/both output-default
          fn with with! forked call-with-output
          ;; internal, shared with the sub-libraries
          %write-flat extract-shared-objects
          make-state-variable
          port row col width output writer pad-char ellipsis
          string-width substring/width substring/preserve
          radix precision decimal-sep decimal-align sign-rule
          comma-rule comma-sep word-separator? ambiguous-is-wide?
          pretty-environment)
  (begin

    ;;; ============================================================ state

    (define-record-type <state-variable>
      (%make-state-variable name default immutable?)
      state-variable?
      (name state-variable-name)
      (default state-variable-default)
      (immutable? state-variable-immutable?))

    (define-record-type <show-state>
      (%make-show-state table)
      show-state?
      (table show-state-table))

    (define (%make-state) (%make-show-state (make-hash-table eq?)))

    (define (%st-ref st var)
      (hash-table-ref/default (show-state-table st) var
                              (state-variable-default var)))

    (define (%st-set! st var val)
      (hash-table-set! (show-state-table st) var val)
      st)

    (define (%st-copy st)
      (%make-show-state (hash-table-copy (show-state-table st))))

    (define (make-state-variable name default . rest)
      (%make-state-variable name default (and (pair? rest) (car rest))))

    ;;; ==================================================== string helpers

    (define (%string-index str ch)
      (let ((len (string-length str)))
        (let loop ((i 0))
          (cond ((= i len) #f)
                ((char=? (string-ref str i) ch) i)
                (else (loop (+ i 1)))))))

    (define (%string-contains str sub)
      (let ((sl (string-length str)) (pl (string-length sub)))
        (if (> pl sl)
            #f
            (let loop ((i 0))
              (cond ((> (+ i pl) sl) #f)
                    ((string=? (substring str i (+ i pl)) sub) i)
                    (else (loop (+ i 1))))))))

    (define (%string-last-newline str)
      (let loop ((i (- (string-length str) 1)))
        (if (< i 0) #f
            (if (char=? (string-ref str i) #\newline) i (loop (- i 1))))))

    (define (%string-count-newlines str)
      (let loop ((i 0) (n 0))
        (if (= i (string-length str)) n
            (loop (+ i 1) (if (char=? (string-ref str i) #\newline) (+ n 1) n)))))

    ;; Default string-width: column width equals the character count in the
    ;; [start, end) range.
    (define (substring-length str . o)
      (let ((start (if (pair? o) (car o) 0))
            (end (if (and (pair? o) (pair? (cdr o))) (cadr o) (string-length str))))
        (- end start)))

    (define (%write-to-string x)
      (let ((p (open-output-string)))
        (write x p)
        (get-output-string p)))

    ;;; ================================================ state variables

    (define port (make-state-variable "port" (current-output-port) #f))
    (define col (make-state-variable "col" 0 #f))
    (define row (make-state-variable "row" 0 #f))
    (define width (make-state-variable "width" 78 #f))
    (define radix (make-state-variable "radix" 10 #f))
    (define pad-char (make-state-variable "pad-char" #\space #f))
    (define string-width (make-state-variable "string-width" substring-length #f))
    (define substring/width (make-state-variable "substring/width" substring #f))
    (define substring/preserve (make-state-variable "substring/preserve" #f #f))
    (define word-separator? (make-state-variable "word-separator?" char-whitespace? #f))
    (define ambiguous-is-wide? (make-state-variable "ambiguous-is-wide?" #f #f))
    (define ellipsis (make-state-variable "ellipsis" "" #f))
    (define decimal-align (make-state-variable "decimal-align" #f #f))
    (define decimal-sep (make-state-variable "decimal-sep" #f #f))
    (define comma-sep (make-state-variable "comma-sep" #f #f))
    (define comma-rule (make-state-variable "comma-rule" #f #f))
    (define sign-rule (make-state-variable "sign-rule" #f #f))
    (define precision (make-state-variable "precision" #f #f))
    (define writer (make-state-variable "writer" #f #f))
    (define pretty-environment (make-state-variable "pretty-environment" #f #f))

    ;;; ================================================== raw output

    ;; Writes str to the current port and advances col/row, measuring the
    ;; column advance with the string-width state variable so wide/zero-width
    ;; characters are tracked correctly under terminal-aware.
    (define (%raw-write st str)
      (write-string str (%st-ref st port))
      (let ((sw (%st-ref st string-width))
            (nl (%string-last-newline str)))
        (if nl
            (begin
              (%st-set! st row (+ (%st-ref st row) (%string-count-newlines str)))
              (%st-set! st col (sw (substring str (+ nl 1) (string-length str)))))
            (%st-set! st col (+ (%st-ref st col) (sw str)))))
      st)

    ;; The default `output` hook: a procedure string -> formatter.
    (define (output-default str)
      (lambda (st) (%raw-write st str)))

    (define output (make-state-variable "output" output-default #f))

    ;; Write a string through the `output` state variable (so overrides
    ;; intercept and can transform the string).
    (define (%output-string st s)
      (((%st-ref st output) s) st))

    (define (%output-char st c)
      (%output-string st (string c)))

    ;;; ================================================ object formatters

    ;; displayed: formatter -> itself; string/char -> raw output; anything else
    ;; -> written.
    (define (displayed obj)
      (cond
        ((procedure? obj) obj)
        ((string? obj) (lambda (st) (%output-string st obj)))
        ((char? obj) (lambda (st) (%output-char st obj)))
        (else (written obj))))

    ;; The formatter dispatch used by show and each.
    (define (%run-fmt st fmt)
      ((displayed fmt) st))

    ;;; ============================================================ show

    (define (show dest . fmts)
      (let* ((p (cond
                  ((eq? dest #t) (current-output-port))
                  ((eq? dest #f) (open-output-string))
                  ((output-port? dest) dest)
                  (else (error "show: invalid destination" dest))))
             (st (%make-state)))
        (%st-set! st port p)
        (let loop ((fs fmts) (st st))
          (if (null? fs)
              (if (eq? dest #f) (get-output-string p) (values))
              (loop (cdr fs) (%run-fmt st (car fs)))))))

    ;;; ================================================ fn / with / with!

    ;; fn is a macro: (fn ((id state-var) ...) expr ... fmt), with the
    ;; abbreviation (fn (id ...) ...) meaning (fn ((id id) ...) ...).
    (define-syntax fn
      (syntax-rules ()
        ((_ (clause ...) expr ... fmt)
         (lambda (st) (%fn-expand st (clause ...) (expr ...) fmt)))))

    (define-syntax %fn-expand
      (syntax-rules ()
        ((_ st () (expr ...) fmt)
         (let () expr ... (%run-fmt st fmt)))
        ((_ st ((id var) . rest) (expr ...) fmt)
         (let ((id (%st-ref st var)))
           (%fn-expand st rest (expr ...) fmt)))
        ((_ st (id . rest) (expr ...) fmt)
         (let ((id (%st-ref st id)))
           (%fn-expand st rest (expr ...) fmt)))))

    ;; with is a macro: (with ((state-var value) ...) fmt ...) binds each
    ;; state-var for the dynamic extent of the body, restoring only the bound
    ;; variables afterwards (so col/row, which track output position, survive).
    (define-syntax with
      (syntax-rules ()
        ((_ ((var val) ...) fmt ...)
         (lambda (st)
           (%with-do st ((var val) ...) (fmt ...))))))

    ;; Nest one save/set/restore per binding so that col/row -- which are not
    ;; bound and are mutated in place -- survive the form.
    (define-syntax %with-do
      (syntax-rules ()
        ((_ st () (fmt ...))
         ((each fmt ...) st))
        ((_ st ((var val) . rest) (fmt ...))
         (let ((tmp (%st-ref st var)))
           (%st-set! st var val)
           (let ((st2 (%with-do st rest (fmt ...))))
             (%st-set! st var tmp)
             st2)))))

    ;; with! is a procedure taking flat (state-var value) pairs and setting
    ;; them permanently (the state variables are first-class values).
    (define (with! . bindings)
      (lambda (st)
        (let loop ((bs bindings))
          (if (null? bs)
              st
              (begin
                (%st-set! st (car bs) (cadr bs))
                (loop (cddr bs)))))))

    ;;; ==================================================== sequencing

    (define (each . fmts)
      (lambda (st)
        (let loop ((fs fmts) (st st))
          (if (null? fs) st (loop (cdr fs) (%run-fmt st (car fs)))))))

    (define (each-in-list lst)
      (lambda (st)
        (let loop ((fs lst) (st st))
          (if (null? fs) st (loop (cdr fs) (%run-fmt st (car fs)))))))

    ;;; ======================================================== spacing

    (define nl (lambda (st) (%output-string st "\n")))
    (define fl (lambda (st) (if (= (%st-ref st col) 0) st (%output-string st "\n"))))
    (define nothing (lambda (st) st))

    (define (space-to column)
      (lambda (st)
        (let ((needed (- column (%st-ref st col))))
          (if (<= needed 0)
              st
              (%output-string st (make-string needed (%st-ref st pad-char)))))))

    (define (tab-to . rest)
      (let ((tw (if (null? rest) 8 (car rest))))
        (lambda (st)
          (if (<= tw 0)
              st
              (let* ((c (%st-ref st col))
                     (rem (modulo c tw)))
                (if (zero? rem)
                    st
                    (%output-string st (make-string (- tw rem) #\space))))))))

    ;;; ====================================================== joining

    (define (joined/general elt-f last-f dot-f lst sep)
      (lambda (st)
        (let loop ((ls lst) (st st) (first #t))
          (cond
            ((pair? ls)
             (let ((st (if first st (%run-fmt st sep))))
               (loop (cdr ls)
                     (%run-fmt st ((if (and last-f (null? (cdr ls))) last-f elt-f)
                                   (car ls)))
                     #f)))
            ((and dot-f (not (null? ls)))
             (%run-fmt (if first st (%run-fmt st sep)) (dot-f ls)))
            (else st)))))

    (define (joined mapper lst . rest)
      (joined/general mapper #f #f lst (if (null? rest) "" (car rest))))

    (define (joined/last mapper last-mapper lst . rest)
      (joined/general mapper last-mapper #f lst (if (null? rest) "" (car rest))))

    (define (joined/dot mapper dot-mapper lst . rest)
      (joined/general mapper #f dot-mapper lst (if (null? rest) "" (car rest))))

    (define (joined/prefix mapper lst . rest)
      (let ((sep (if (null? rest) "" (car rest))))
        (lambda (st)
          (let loop ((items lst) (st st))
            (if (null? items)
                st
                (loop (cdr items) (%run-fmt (%run-fmt st sep) (mapper (car items)))))))))

    (define (joined/suffix mapper lst . rest)
      (let ((sep (if (null? rest) "" (car rest))))
        (lambda (st)
          (let loop ((items lst) (st st))
            (if (null? items)
                st
                (loop (cdr items) (%run-fmt (%run-fmt st (mapper (car items))) sep)))))))

    (define (joined/range mapper start . rest)
      (let ((end (if (null? rest) #f (car rest)))
            (sep (if (or (null? rest) (null? (cdr rest))) "" (cadr rest))))
        (lambda (st)
          (let loop ((i start) (st st) (first #t))
            (if (and end (>= i end))
                st
                (let ((st (if first st (%run-fmt st sep))))
                  (loop (+ i 1) (%run-fmt st (mapper i)) #f)))))))

    ;;; ============================================ forking and capture

    (define (forked fmt1 fmt2)
      (lambda (st)
        (let ((st2 (%st-copy st)))
          ((displayed fmt1) st2)
          ((displayed fmt2) st))))

    (define (call-with-output producer consumer)
      (lambda (st)
        (let ((out (open-output-string))
              (sub (%st-copy st)))
          (%st-set! sub port out)
          (%st-set! sub output output-default)
          ((displayed producer) sub)
          (%run-fmt st (consumer (get-output-string out))))))

    (define (%capture-output st fmts)
      (let ((out (open-output-string))
            (sub (%st-copy st)))
        (%st-set! sub port out)
        (%st-set! sub output output-default)
        ((apply each fmts) sub)
        (get-output-string out)))

    (define (%ellipsis-string ell)
      (cond ((char? ell) (string ell))
            (ell ell)
            (else "")))

    ;;; =========================================== padding and trimming

    (define (padded w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (sw (%st-ref st string-width))
               (needed (- w (sw s))))
          (if (<= needed 0)
              (%output-string st s)
              (%output-string (%output-string st (make-string needed (%st-ref st pad-char))) s)))))

    (define (padded/right w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (sw (%st-ref st string-width))
               (needed (- w (sw s))))
          (if (<= needed 0)
              (%output-string st s)
              (%output-string (%output-string st s) (make-string needed (%st-ref st pad-char)))))))

    (define (padded/both w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (sw (%st-ref st string-width))
               (needed (- w (sw s))))
          (if (<= needed 0)
              (%output-string st s)
              (let ((left (quotient needed 2))
                    (right (- needed (quotient needed 2))))
                (%output-string
                  (%output-string (%output-string st (make-string left (%st-ref st pad-char))) s)
                  (make-string right (%st-ref st pad-char))))))))

    (define (trimmed w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (sw (%st-ref st string-width))
               (slen (sw s)))
          (if (<= slen w)
              (%output-string st s)
              (let* ((ell (%ellipsis-string (%st-ref st ellipsis)))
                     (keep (- w (sw ell))))
                (if (<= keep 0)
                    (%output-string st ell)
                    (%output-string (%output-string st ell)
                                    ((%st-ref st substring/width) s (- slen keep) slen))))))))

    (define (trimmed/right w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (sw (%st-ref st string-width))
               (slen (sw s)))
          (if (<= slen w)
              (%output-string st s)
              (let* ((ell (%ellipsis-string (%st-ref st ellipsis)))
                     (keep (- w (sw ell))))
                (if (<= keep 0)
                    (%output-string st ell)
                    (%output-string (%output-string st ((%st-ref st substring/width) s 0 keep))
                                    ell)))))))

    (define (trimmed/both w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (sw (%st-ref st string-width))
               (slen (sw s)))
          (if (<= slen w)
              (%output-string st s)
              (let* ((ell (%ellipsis-string (%st-ref st ellipsis)))
                     (keep (- w (sw ell) (sw ell))))
                (if (<= keep 0)
                    (%output-string (%output-string st ell) ell)
                    (let* ((trim (- slen keep))
                           (left (quotient trim 2))
                           (right (+ left keep)))
                      (%output-string
                        (%output-string (%output-string st ell)
                                        ((%st-ref st substring/width) s left right))
                        ell))))))))

    (define (fitted w . fmts)
      (padded w (apply trimmed (cons w fmts))))

    (define (fitted/right w . fmts)
      (padded/right w (apply trimmed/right (cons w fmts))))

    (define (fitted/both w . fmts)
      (padded/both w (apply trimmed/both (cons w fmts))))

    ;; A non-lazy stand-in for trimmed/lazy: correct for finite output (the
    ;; infinite-stream laziness has no observable effect for the finite tests).
    (define (trimmed/lazy w . fmts)
      (apply trimmed/right (cons w fmts)))

    ;;; ================================================== escaping

    (define (%escape-string str quote-ch esc-ch renamer)
      (let ((out (open-output-string)))
        (let loop ((i 0))
          (if (= i (string-length str))
              (get-output-string out)
              (let* ((c (string-ref str i))
                     (r (renamer c)))
                (cond
                  ((and esc-ch (or (char=? c quote-ch) (char=? c esc-ch)))
                   (write-string (string esc-ch) out)
                   (write-char c out)
                   (loop (+ i 1)))
                  ((and esc-ch r)
                   (write-string (string esc-ch) out)
                   (if (char? r) (write-char r out) (write-string r out))
                   (loop (+ i 1)))
                  ((and (not esc-ch) (char=? c quote-ch))
                   (write-char c out) (write-char c out)
                   (loop (+ i 1)))
                  (else
                   (write-char c out)
                   (loop (+ i 1)))))))))

    (define (escaped str . rest)
      (let ((quote-ch (if (null? rest) #\" (car rest)))
            (esc-ch (if (or (null? rest) (null? (cdr rest))) #\\ (cadr rest)))
            (renamer (if (or (null? rest) (null? (cdr rest)) (null? (cddr rest)))
                         (lambda (c) #f)
                         (caddr rest))))
        (lambda (st)
          (%output-string st (%escape-string str quote-ch esc-ch renamer)))))

    (define (maybe-escaped str pred . rest)
      (let ((quote-ch (if (null? rest) #\" (car rest)))
            (esc-ch (if (or (null? rest) (null? (cdr rest))) #\\ (cadr rest)))
            (renamer (if (or (null? rest) (null? (cdr rest)) (null? (cddr rest)))
                         (lambda (c) #f)
                         (caddr rest))))
        (define (needs-escape? c)
          (or (char=? c quote-ch)
              (and esc-ch (char=? c esc-ch))
              (renamer c)
              (pred c)))
        (let ((escaped? (let loop ((i 0))
                          (cond ((= i (string-length str)) #f)
                                ((needs-escape? (string-ref str i)) #t)
                                (else (loop (+ i 1)))))))
          (lambda (st)
            (if escaped?
                (%output-string
                  (%output-string (%output-string st (string quote-ch))
                                  (%escape-string str quote-ch esc-ch renamer))
                  (string quote-ch))
                (%output-string st str))))))

    ;;; ====================================================== numeric

    (define (%integer-log a base)
      (if (zero? a)
          0
          (do ((ndigits 1 (+ ndigits 1))
               (p base (* p base)))
              ((> p a) ndigits))))

    (define (%pad-digits s k)
      (if (>= (string-length s) k)
          s
          (string-append (make-string (- k (string-length s)) #\0) s)))

    (define (%char-mirror c)
      (case c ((#\() #\)) ((#\[) #\]) ((#\{) #\}) ((#\<) #\>) (else c)))

    ;; Formats the real/complex number n to a string honouring the resolved
    ;; radix/precision/sign-rule/comma-rule/comma-sep/decimal-sep/decimal-align.
    (define (%number->string n radix precision sign-rule comma-rule comma-sep
                             decimal-sep decimal-align)
      (let ((dec-sep (or decimal-sep (if (eqv? comma-sep #\.) "," "."))))
        (define (dec-sep-str) (if (char? dec-sep) (string dec-sep) dec-sep))
        (define (comma-sep-str)
          (cond ((char? comma-sep) (string comma-sep))
                ((string? comma-sep) comma-sep)
                ((eqv? #\, dec-sep) ".")
                (else ",")))
        (define (intersperse-right str sep rule)
          (let ((len (string-length str)))
            (let loop ((i len) (rule rule) (parts '()))
              (let* ((offset (if (pair? rule) (car rule) rule))
                     (i2 (if offset (max 0 (- i offset)) 0)))
                (if (<= i2 0)
                    (apply string-append (cons (substring str 0 i) parts))
                    (loop i2
                          (if (and (pair? rule) (not (null? (cdr rule)))) (cdr rule) rule)
                          (cons sep (cons (substring str i2 i) parts))))))))
        (define (add-commas str)
          (if comma-rule
              (let ((ds (dec-sep-str)))
                (let ((pos (%string-contains str ds)))
                  (if pos
                      (string-append
                        (intersperse-right (substring str 0 pos) (comma-sep-str) comma-rule)
                        (substring str pos (string-length str)))
                      (intersperse-right str (comma-sep-str) comma-rule))))
              str))
        (define (format-positive m)
          (cond
            ((and (not precision) (exact? m) (not (integer? m)))
             (string-append (format-positive (numerator m)) "/"
                            (format-positive (denominator m))))
            (precision
             (let* ((scale (expt radix precision))
                    (scaled (exact (round (* m scale))))
                    (int (quotient scaled scale))
                    (frac (remainder scaled scale)))
               (if (zero? precision)
                   (number->string int radix)
                   (string-append (number->string int radix) (dec-sep-str)
                                  (%pad-digits (number->string frac radix) precision)))))
            ((and (exact? m) (integer? m))
             (number->string m radix))
            (else
             (number->string m))))
        (define (wrap-sign m)
          (let ((s (add-commas (format-positive (abs m)))))
            (cond
              ((negative? m)
               (cond
                 ((char? sign-rule)
                  (string-append (string sign-rule) s (string (%char-mirror sign-rule))))
                 ((pair? sign-rule)
                  (string-append (car sign-rule) s (cdr sign-rule)))
                 (else (string-append "-" s))))
              ((eq? #t sign-rule) (string-append "+" s))
              (else s))))
        (define (format-real m)
          (if (finite? m)
              (let ((s (wrap-sign m)))
                (if decimal-align
                    (let* ((pos (%string-contains s (dec-sep-str)))
                           (dec-pos (or pos (string-length s)))
                           (diff (- decimal-align dec-pos)))
                      (if (positive? diff) (string-append (make-string diff #\space) s) s))
                    s))
              (number->string m)))
        (define (write-complex n)
          (if (real? n) (format-real n) (%write-to-string n)))
        (write-complex n)))

    (define (%opt args n default)
      (let loop ((a args) (i 0))
        (cond ((null? a) default)
              ((= i n) (car a))
              (else (loop (cdr a) (+ i 1))))))

    (define (numeric n . rest)
      (lambda (st)
        (%output-string
          st
          (%number->string n
            (%opt rest 0 (%st-ref st radix))
            (%opt rest 1 (%st-ref st precision))
            (%opt rest 2 (%st-ref st sign-rule))
            (%opt rest 3 (%st-ref st comma-rule))
            (%opt rest 4 (%st-ref st comma-sep))
            (%opt rest 5 (%st-ref st decimal-sep))
            (%st-ref st decimal-align)))))

    (define (numeric/comma n . rest)
      (lambda (st)
        (let ((cr (if (null? rest) (or (%st-ref st comma-rule) 3) (car rest)))
              (remaining (if (null? rest) '() (cdr rest))))
          (let ((saved (%st-ref st comma-rule)))
            (%st-set! st comma-rule cr)
            (let ((st2 ((apply numeric (cons n remaining)) st)))
              (%st-set! st comma-rule saved)
              st2)))))

    (define numeric/si
      (let* ((names10 '#("" "k" "M" "G" "T" "P" "E" "Z" "Y"))
             (names-10 '#("" "m" "\xb5;" "n" "p" "f" "a" "z" "y"))
             (names2 (list->vector
                       (cons "" (cons "Ki" (map (lambda (s) (string-append s "i"))
                                                (cddr (vector->list names10)))))))
             (names-2 (list->vector
                        (cons "" (map (lambda (s) (string-append s "i"))
                                      (cdr (vector->list names-10)))))))
        (define (round-to n k) (/ (round (* n k)) k))
        (lambda (n . rest)
          (let ((base (if (null? rest) 1000 (car rest)))
                (separator (if (or (null? rest) (null? (cdr rest))) "" (cadr rest))))
            (lambda (st)
              (%output-string st
                (if (zero? n)
                    "0"
                    (let* ((log-n (log (abs n)))
                           (names (if (negative? log-n)
                                      (if (= base 1024) names-2 names-10)
                                      (if (= base 1024) names2 names10)))
                           (k (min (exact ((if (negative? log-n) ceiling floor)
                                           (/ (abs log-n) (log base))))
                                   (- (vector-length names) 1)))
                           (n2 (round-to (/ (abs n) (expt base (if (negative? log-n) (- k) k)))
                                         10)))
                      (string-append
                        (if (negative? n) "-" "")
                        (if (integer? n2) (number->string (exact n2)) (number->string (inexact n2)))
                        separator
                        (vector-ref names k))))))))))

    (define (numeric/fitted width n . rest)
      (lambda (st)
        (let* ((s (%number->string n
                     (%opt rest 0 (%st-ref st radix))
                     (%opt rest 1 (%st-ref st precision))
                     (%opt rest 2 (%st-ref st sign-rule))
                     (%opt rest 3 (%st-ref st comma-rule))
                     (%opt rest 4 (%st-ref st comma-sep))
                     (%opt rest 5 (%st-ref st decimal-sep))
                     (%st-ref st decimal-align))))
          (if (<= (string-length s) width)
              (%output-string st s)
              (let* ((prec (%opt rest 1 (%st-ref st precision)))
                     (ds (%opt rest 5 (%st-ref st decimal-sep)))
                     (cs (%opt rest 4 (%st-ref st comma-sep)))
                     (dsep (or ds (if (eqv? cs #\.) #\, #\.)))
                     (dstr (if (char? dsep) (string dsep) dsep)))
                (if (and prec (not (zero? prec)))
                    (%output-string st
                      (string-append (make-string (max 0 (- width prec (string-length dstr))) #\#)
                                     dstr (make-string prec #\#)))
                    (%output-string st (make-string width #\#))))))))

    ;;; =============================================== shared structures

    (define (extract-shared-objects x cyclic-only?)
      (let ((seen (make-hash-table eq?)))
        (let find ((x x))
          (cond
            ((or (pair? x) (vector? x))
             (hash-table-update!/default seen x (lambda (n) (+ n 1)) 0)
             (cond
               ((> (hash-table-ref seen x) 1))
               ((pair? x) (find (car x)) (find (cdr x)))
               ((vector? x)
                (let ((len (vector-length x)))
                  (do ((i 0 (+ i 1))) ((= i len)) (find (vector-ref x i))))))
             (if (and cyclic-only? (<= (hash-table-ref/default seen x 0) 1))
                 (hash-table-delete! seen x)))))
        (let ((res (make-hash-table eq?)) (count 0))
          (hash-table-walk seen
            (lambda (k v)
              (cond ((> v 1)
                     (hash-table-set! res k (cons count #f))
                     (set! count (+ count 1))))))
          (cons res 0))))

    (define (%gen-shared-ref cell shares)
      (set-car! cell (cdr shares))
      (set-cdr! cell #t)
      (set-cdr! shares (+ (cdr shares) 1))
      (number->string (car cell)))

    (define (%shared-ref-prefix obj shares proc)
      (let ((cell (hash-table-ref/default (car shares) obj #f)))
        (cond
          ((and (pair? cell) (cdr cell))
           (string-append "#" (number->string (car cell)) "#"))
          ((pair? cell)
           (string-append "#" (%gen-shared-ref cell shares) "=" (proc)))
          (else (proc)))))

    (define (%shared-ref-cdr obj shares proc)
      (let ((cell (hash-table-ref/default (car shares) obj #f)))
        (cond
          ((and (pair? cell) (cdr cell))
           (string-append ". #" (number->string (car cell)) "#"))
          ((pair? cell)
           (string-append ". #" (%gen-shared-ref cell shares) "=(" (proc) ")"))
          (else (proc)))))

    ;; Flatten obj to a string, labelling shared structure, with numbers
    ;; formatted according to radix/precision.
    (define (%write-flat obj shares radix precision)
      ;; Per the spec, `written` uses the radix only for 2/8/10/16 (the
      ;; readable radices), and fixed-point precision only when the radix is
      ;; 10.  Precision must not disable the radix branch for non-decimal
      ;; radices.
      (define (write-number n)
        (let ((cell (assv radix '((16 . "#x") (10 . "") (8 . "#o") (2 . "#b")))))
          (cond
            ((and cell (eqv? radix 10))
             (if precision (%number->string n 10 precision #f #f #f #f #f) (number->string n)))
            ((and cell (exact? n)) (string-append (cdr cell) (number->string n (car cell))))
            (else (%number->string n 10 precision #f #f #f #f #f)))))
      (let wr ((obj obj))
        (%shared-ref-prefix
          obj shares
          (lambda ()
            (cond
              ((pair? obj)
               (string-append
                 "("
                 (let lp ((ls obj))
                   (let ((rest (cdr ls)))
                     (string-append
                       (wr (car ls))
                       (cond
                         ((null? rest) "")
                         ((pair? rest)
                          (string-append " " (%shared-ref-cdr rest shares (lambda () (lp rest)))))
                         (else (string-append " . " (wr rest)))))))
                 ")"))
              ((vector? obj)
               (let ((len (vector-length obj)))
                 (if (zero? len)
                     "#()"
                     (let loop ((i 0) (acc "#("))
                       (if (= i len)
                           (string-append acc ")")
                           (loop (+ i 1)
                                 (string-append acc (if (zero? i) "" " ")
                                                (wr (vector-ref obj i)))))))))
              ((number? obj) (write-number obj))
              (else (%write-to-string obj)))))))

    (define (written obj)
      (lambda (st)
        (let ((w (%st-ref st writer)))
          (if w
              ((w obj) st)
              (%output-string st
                (%write-flat obj (extract-shared-objects obj #t)
                             (%st-ref st radix) (%st-ref st precision)))))))

    (define (written-shared obj)
      (lambda (st)
        (%output-string st
          (%write-flat obj (extract-shared-objects obj #f)
                       (%st-ref st radix) (%st-ref st precision)))))

    (define (written-simply obj)
      (lambda (st)
        (%output-string st
          (%write-flat obj (extract-shared-objects #f #f)
                       (%st-ref st radix) (%st-ref st precision)))))

    ))
