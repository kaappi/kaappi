;; Regression test for #807: deep copy must preserve eq? identity
;; for shared strings and bytevectors across thread boundaries.

(import (scheme base) (srfi 18))

(define (test name expected actual)
  (unless (equal? expected actual)
    (display "FAIL: ") (display name)
    (display " expected ") (display expected)
    (display " got ") (display actual) (newline)
    (exit 1)))

;; String sharing
(let* ((s (make-string 3 #\a))
       (lst (list s s)))
  (test "parent string eq?" #t (eq? (car lst) (cadr lst)))
  (let ((result (thread-join!
                 (thread-start!
                  (make-thread
                   (lambda ()
                     (let ((eq-result (eq? (car lst) (cadr lst))))
                       (string-set! (car lst) 0 #\z)
                       (list eq-result
                             (string-ref (car lst) 0)
                             (string-ref (cadr lst) 0)))))))))
    (test "child string eq?" #t (car result))
    (test "child string mutation visible via shared ref"
          #\z (cadr result))
    (test "child string mutation visible via second ref"
          #\z (caddr result))))

;; Bytevector sharing
(let* ((bv (make-bytevector 3 0))
       (lst (list bv bv)))
  (test "parent bv eq?" #t (eq? (car lst) (cadr lst)))
  (let ((result (thread-join!
                 (thread-start!
                  (make-thread
                   (lambda ()
                     (let ((eq-result (eq? (car lst) (cadr lst))))
                       (bytevector-u8-set! (car lst) 0 42)
                       (list eq-result
                             (bytevector-u8-ref (car lst) 0)
                             (bytevector-u8-ref (cadr lst) 0)))))))))
    (test "child bv eq?" #t (car result))
    (test "child bv mutation visible via shared ref"
          42 (cadr result))
    (test "child bv mutation visible via second ref"
          42 (caddr result))))

(display "OK") (newline)
