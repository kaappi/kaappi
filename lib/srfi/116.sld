;;; SRFI 116 — Immutable List Library
;;; Immutable pairs (ipairs) implemented as regular pairs
;;; (Kaappi doesn't enforce immutability at the type level,
;;; but the API contract is immutable)
(define-library (srfi 116)
  (import (scheme base) (srfi 1))
  (export ipair ilist ipair* icar icdr
          ilist? ipair? inull? inull
          icaar icadr icdar icddr
          ilist-ref ilist-tail ilength
          iappend ireverse imap ifor-each
          ifold ifold-right
          ifilter iremove
          ifind iany ievery
          ilist->list list->ilist)
  (begin

    (define (ipair a b) (cons a b))
    (define (ilist . args) args)
    (define (ipair* . args)
      (if (null? (cdr args)) (car args)
          (cons (car args) (apply ipair* (cdr args)))))
    (define icar car)
    (define icdr cdr)
    (define ilist? list?)
    (define ipair? pair?)
    (define inull? null?)
    (define inull '())
    (define icaar caar)
    (define icadr cadr)
    (define icdar cdar)
    (define icddr cddr)
    (define ilist-ref list-ref)
    (define ilist-tail list-tail)
    (define ilength length)
    (define iappend append)
    (define ireverse reverse)
    (define imap map)
    (define ifor-each for-each)
    (define ifold fold)
    (define ifold-right fold-right)
    (define ifilter filter)
    (define iremove remove)
    (define ifind find)
    (define iany any)
    (define ievery every)
    (define ilist->list list-copy)
    (define list->ilist list-copy)))
