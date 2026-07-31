;; Depends on util and defines module-level state in its begin block. The
;; multi-import is the point (kaappi#703): when one of its import sets raises a
;; CompileError, handleDefineLibrary must still run this begin block and
;; register the exports, or `registry` stays UNDEFINED and `lookup` dies.
(define-library (bundle703 app)
  (import (scheme base) (srfi 69) (bundle703 util))
  (export app-greet lookup register!)
  (begin
    (define registry (make-hash-table string=? string-hash))
    (define (register! key val) (hash-table-set! registry key val))
    (define (lookup key) (hash-table-ref/default registry key #f))
    (define (app-greet name) (register! name #t) (greet name))))
