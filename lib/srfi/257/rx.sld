;;; SRFI 257 rx sublibrary: regexp match patterns over SRFI 115 regexps and
;;; SRFI 264 SSRE strings.
;;;
;;; Ported to Kaappi from Sergei Egorov's reference implementation, with one
;;; fix: the reference's ~/all+ pattern calls `regexp-search-all`, which is
;;; neither defined in the reference nor part of SRFI 115 (upstream reference
;;; bug), so the pattern raised an unbound-variable error on every use. The
;;; specification defines ~/all+ as ~/all constrained to fail when the regexp
;;; matches no substring, so the missing procedure is the list-of-submatch-
;;; lists variant that reports "no matches" as an empty list instead of the
;;; circular list of empty lists ~/all itself needs; it is defined below.
;;;
;;; SPDX-FileCopyrightText: 2025 Sergei Egorov
;;; SPDX-License-Identifier: MIT

(define-library (srfi 257 rx)
  (import (scheme base) (srfi 115) (srfi 257) (srfi 264))
  (export
    rx ; re-exported from srfi 115
    ~/ ~/sub ~/any ~/all ~/all+ ~/etc ~/etcse ~/etc+
    ~/extracted ~/split ~/partitioned)

(begin

(define (ssorx x)
  (cond ((regexp? x) x)
        ((string? x) (ssre->regexp x)) ; assumed to be cached
        (else (error "regexp match pattern expects an SSRE string or a regexp argument" x))))

(define (regexp-search-all/list-of-matches re str)
  (define (kons i m str acc) (cons m acc))
  (define (finish i m str acc) (reverse acc))
  (regexp-fold re kons '() str finish))

(define (regexp-search-all/list-of-match-lists re str)
  (define (kons i m str acc)
    (cons (regexp-match->list m) acc))
  (define (finish i m str acc)
    (reverse acc))
  (regexp-fold re kons '() str finish))

(define (regexp-search-all/list-of-submatch-lists re str)
  (define (empty-lists) ; returned on no matches
    (let ((el (list '()))) (set-cdr! el el) el))
  (define (kons i m str acc)
    (let ((l (regexp-match->list m)))
      (if (null? acc) (map list l) (map cons l acc))))
  (define (finish i m str acc)
    (if (null? acc) (empty-lists) (map reverse acc)))
  (regexp-fold re kons '() str finish))

; Kaappi addition: see the header note. Same as the list-of-submatch-lists
; variant above, but a run with no matches yields '() rather than a circular
; list of empty lists, so ~/all+'s ~pair? guard can reject it.
(define (regexp-search-all re str)
  (define (kons i m str acc)
    (let ((l (regexp-match->list m)))
      (if (null? acc) (map list l) (map cons l acc))))
  (define (finish i m str acc)
    (if (null? acc) '() (map reverse acc)))
  (regexp-fold re kons '() str finish))

(define-match-pattern ~/ ()
  ((~/ x)
   (~test (lambda (s) (and (string? s) (regexp-matches? (ssorx x) s)))))
  ((~/ x spat ...) ; $0, $1, ...
   (~test (lambda (s) (and (string? s) (regexp-matches (ssorx x) s))) =>
     (~prop regexp-match->list => (~list* spat ... _)))))

(define-match-pattern ~/sub ()
  ((~/sub x)
   (~test (lambda (s) (and (string? s) (regexp-search (ssorx x) s)))))
  ((~/sub x spat ...) ; $0, $1, ...
   (~test (lambda (s) (and (string? s) (regexp-search (ssorx x) s))) =>
     (~prop regexp-match->list => (~list* spat ... _)))))

(define-syntax any:start
  (syntax-rules () ((_ xv try f) (if (pair? xv) (try xv) (f)))))
(define-syntax any:head
  (syntax-rules () ((_ xv) (regexp-match->list (car xv)))))
(define-syntax any:tail
  (syntax-rules () ((_ try f xv) (if (pair? (cdr xv)) (try (cdr xv)) (f)))))

(define-match-pattern ~/any ()
  ((~/any x spat ...) ; $0, $1, ...
   (~string? (~prop (lambda (s) (regexp-search-all/list-of-matches (ssorx x) s)) =>
                (~iterate any:start any:head any:tail (l) (~list* spat ... _))))))

(define-match-pattern ~/all ()
  ((~/all x s*pat ...) ; $0*, $1*, ...
   (~string? (~prop (lambda (s) (regexp-search-all/list-of-submatch-lists (ssorx x) s)) =>
                (~list* s*pat ... _)))))

; The rule heads below read ~/+ and ~/s rather than the pattern's own name.
; That is upstream's spelling and it is inert: as in syntax-rules, the head of
; a define-match-pattern rule is ignored, so it is left as the reference has it.
(define-match-pattern ~/all+ ()
  ((~/+ x s*pat ...) ; $0*, $1*, ...
   (~string? (~prop (lambda (s) (regexp-search-all (ssorx x) s)) =>
                (~pair? (~list* s*pat ... _))))))

(define-match-pattern ~/etc ()
  ((~/etc x spat ...) ; $0, $1, ...
   (~string? (~prop (lambda (s) (regexp-search-all/list-of-match-lists (ssorx x) s)) =>
                (~etc (~list* spat ... _))))))

(define-match-pattern ~/etc+ ()
  ((~/+ x spat ...) ; $0, $1, ...
   (~string? (~prop (lambda (s) (regexp-search-all/list-of-match-lists (ssorx x) s)) =>
                (~pair? (~etc (~list* spat ... _)))))))

(define-match-pattern ~/etcse ()
  ((~/etcse x spat ...) ; $0, $1, ...
   (~string? (~prop (lambda (s) (regexp-search-all/list-of-match-lists (ssorx x) s)) =>
                (~etcse (~list* spat ... _))))))

(define-match-pattern ~/extracted ()
  ((~/extracted x s*pat)
   (~string? (~prop (lambda (s) (regexp-extract (ssorx x) s)) => s*pat))))

(define-match-pattern ~/split ()
  ((~/s x s*pat)
   (~string? (~prop (lambda (s) (regexp-split (ssorx x) s)) => s*pat))))

(define-match-pattern ~/partitioned ()
  ((~/partitioned x s*pat)
   (~string? (~prop (lambda (s) (regexp-partition (ssorx x) s)) => s*pat))))

))
