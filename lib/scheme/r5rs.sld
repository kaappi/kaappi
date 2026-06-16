(define-library (scheme r5rs)
  (import (scheme base) (scheme char) (scheme cxr)
          (scheme inexact) (scheme lazy) (scheme read)
          (scheme write) (scheme eval) (scheme load)
          (scheme file) (scheme case-lambda)
          (scheme process-context) (scheme time))
  (export
    * + - / < <= = > >= abs and append apply
    begin boolean? bytevector?
    caar cadr car cdar cddr cdr ceiling
    char->integer char-alphabetic? char-ci<=? char-ci<? char-ci=?
    char-ci>=? char-ci>? char-downcase char-lower-case? char-numeric?
    char-upcase char-upper-case? char-whitespace? char<=? char<?
    char=? char>=? char>? char? close-input-port close-output-port
    complex? cond cons cos current-input-port current-output-port
    define define-record-type define-syntax denominator display
    do dynamic-wind
    eof-object? eq? equal? eqv? eval even? exact->inexact
    exact? exp expt floor for-each force gcd
    if import inexact->exact inexact? input-port? integer->char
    integer? interaction-environment lambda lcm length let
    let* let-syntax letrec letrec-syntax list list->string
    list->vector list-ref list-tail list? log
    make-string make-vector map max member memq memv min modulo
    negative? newline not null? number->string number? numerator
    odd? open-input-file open-output-file or output-port?
    pair? peek-char positive? procedure? quasiquote quote
    quotient rational? rationalize read read-char real-part
    real? remainder reverse round
    set! set-car! set-cdr! sin sqrt string string->list
    string->number string->symbol string-append string-ci<=?
    string-ci<? string-ci=? string-ci>=? string-ci>? string-copy
    string-length string-ref string-set! string<=? string<?
    string=? string>=? string>? string? substring symbol->string
    symbol? tan truncate values vector vector->list
    vector-fill! vector-length vector-ref vector-set! vector?
    with-exception-handler write write-char zero?
    )
  (begin
    (define interaction-environment environment)
    (define exact->inexact inexact)
    (define inexact->exact exact)))
