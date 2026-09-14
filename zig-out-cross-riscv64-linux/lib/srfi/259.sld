;; SRFI 259: Tagged procedures with type safety
;; <https://srfi.schemers.org/srfi-259/srfi-259.html>
;;
;; A type-safe layer over SRFI 229 tagged procedures. `define-procedure-tag`
;; generatively creates a tagging protocol — a constructor/predicate/accessor
;; triple, much like `define-record-type` — so that only the holder of a
;; protocol's own bindings can attach or read that protocol's tag. One
;; procedure may carry tags from several protocols at once.
;;
;; This is a portable R7RS implementation layered on (srfi 229). The SRFI 259
;; sample implementation in the SRFI's repository targets Chez Scheme's native
;; `make-wrapper-procedure`; this file provides the equivalent behavior on top
;; of the portable SRFI 229 primitives instead.
;;
;; The single SRFI 229 tag carried by a tagged procedure is a private, opaque
;; `<tag-set>` record mapping each protocol's unforgeable key object to that
;; protocol's tag value. Because the record and its accessors are not exported,
;; and each protocol's key is minted freshly (and privately) per
;; `define-procedure-tag` expansion, no code can forge a tag or read another
;; protocol's tag — that is the "type safety" of the title. `<tag-set>` also
;; records the original underlying procedure so re-tagging re-wraps it directly
;; instead of nesting wrappers.
;;
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 the Kaappi authors.
;; The interface it implements is from SRFI 259 by Daphne Preston-Kendal.

(define-library (srfi 259)
  (export define-procedure-tag)
  (import (scheme base)
          (srfi 229))
  (begin

    ;; Private, opaque container for a procedure's per-protocol tags.
    ;;   alist : list of (protocol-key . tag-value)
    ;;   base  : the original, untagged underlying procedure
    (define-record-type <tag-set>
      (make-tag-set alist base)
      tag-set?
      (alist tag-set-alist)
      (base tag-set-base))

    ;; Return alist with protocol-key => value, replacing any existing entry.
    (define (alist-set alist key value)
      (cond ((assq key alist)
             (map (lambda (entry)
                    (if (eq? (car entry) key) (cons key value) entry))
                  alist))
            (else
             (cons (cons key value) alist))))

    ;; Build a fresh procedure behaving exactly like BASE but SRFI 229-tagged
    ;; with the given tag-set. Variadic forwarding preserves all arities.
    (define (wrap base tags)
      (case-lambda/tag tags
        (args (apply base args))))

    ;; #t iff OBJ is one of our tagged procedures carrying protocol KEY.
    ;; Guards `procedure-tag` behind `procedure/tag?` so an ordinary procedure
    ;; is never invoked with SRFI 229's secret probe key.
    (define (protocol-tagged? obj key)
      (and (procedure? obj)
           (procedure/tag? obj)
           (let ((tags (procedure-tag obj)))
             (and (tag-set? tags)
                  (assq key (tag-set-alist tags))
                  #t))))

    ;; The tag value stored for protocol KEY, or an error if absent.
    (define (protocol-tag-ref proc key who)
      (if (protocol-tagged? proc key)
          (cdr (assq key (tag-set-alist (procedure-tag proc))))
          (error "srfi 259: procedure is not tagged in this protocol"
                 who proc)))

    ;; Return a new procedure behaving like UNDERLYING, tagged with VALUE under
    ;; protocol KEY. Tags from other protocols are preserved; a tag already
    ;; present for KEY is replaced.
    (define (make-tagged-procedure underlying key value)
      (cond
        ((not (procedure? underlying))
         (error "srfi 259: not a procedure" underlying))
        ((and (procedure/tag? underlying)
              (tag-set? (procedure-tag underlying)))
         (let* ((old (procedure-tag underlying))
                (base (tag-set-base old)))
           (wrap base (make-tag-set (alist-set (tag-set-alist old) key value)
                                    base))))
        (else
         (wrap underlying
               (make-tag-set (list (cons key value)) underlying)))))

    (define-syntax define-procedure-tag
      (syntax-rules ()
        ((_ constructor predicate accessor)
         (begin
           ;; Unforgeable key identifying this protocol; the quoted name is a
           ;; label only — identity comes from the fresh list object.
           (define protocol-key (list 'constructor))
           (define (constructor tag proc)
             (make-tagged-procedure proc protocol-key tag))
           (define (predicate obj)
             (protocol-tagged? obj protocol-key))
           (define (accessor proc)
             (protocol-tag-ref proc protocol-key 'accessor))))))))
