;; SRFI 229: Tagged Procedures
;; <https://srfi.schemers.org/srfi-229/srfi-229.html>
;;
;; A tagged procedure carries an attached "tag" value alongside its normal
;; behavior. `lambda/tag` / `case-lambda/tag` create one, `procedure/tag?`
;; recognizes one, and `procedure-tag` retrieves the tag.
;;
;; This is the portable R7RS reference implementation, reproduced verbatim
;; (below the header) under its MIT terms. Note the documented limitation of
;; this portable design: every tagged procedure is retained in a global list
;; for identity tracking, so tagged procedures are never garbage-collected.
;; A program that creates a bounded number of them is unaffected.
;;
;; Copyright (C) Marc Nieper-Wißkirchen (2021).  All Rights Reserved.
;;
;; Permission is hereby granted, free of charge, to any person
;; obtaining a copy of this software and associated documentation
;; files (the "Software"), to deal in the Software without
;; restriction, including without limitation the rights to use, copy,
;; modify, merge, publish, distribute, sublicense, and/or sell copies
;; of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
;; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
;; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
;; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

(define-library (srfi 229)
  (export case-lambda/tag
          lambda/tag
          procedure/tag?
          procedure-tag)
  (import (scheme base)
          (scheme case-lambda))
  (begin
    (define *tagged-procedures* '())

    (define key (list 'key))

    (define make-procedure/tag
      (lambda (tag proc)
        (define f
          (case-lambda
            ((arg)
             (if (eq? arg key) tag (proc arg)))
            (arg*
             (apply proc arg*))))
        (set! *tagged-procedures* (cons f *tagged-procedures*))
        f))

    (define-syntax case-lambda/tag
      (syntax-rules ()
        ((case-lambda/tag expr (formals body1 ... body2) ...)
         (make-procedure/tag
          expr
          (case-lambda (formals body1 ... body2) ...)))))

    (define-syntax lambda/tag
      (syntax-rules ()
        ((lambda/tag expr formals body1 ... body2)
         (make-procedure/tag
          expr
          (lambda formals body1 ... body2)))))

    (define procedure/tag?
      (lambda (f)
        (and (memv f *tagged-procedures*) #t)))

    (define procedure-tag
      (lambda (f)
        (f key)))))
