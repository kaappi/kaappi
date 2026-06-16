(define-library (srfi 2)
  (import (scheme base))
  (export and-let*)
  (begin
    (define-syntax and-let*
      (syntax-rules ()
        ((and-let* () body ...)
         (begin body ...))
        ((and-let* ((var expr)) body ...)
         (let ((var expr))
           (if var (begin body ...) #f)))
        ((and-let* ((var1 expr1) (var2 expr2)) body ...)
         (let ((var1 expr1))
           (if var1
               (let ((var2 expr2))
                 (if var2 (begin body ...) #f))
               #f)))
        ((and-let* ((var1 expr1) (var2 expr2) (var3 expr3)) body ...)
         (let ((var1 expr1))
           (if var1
               (let ((var2 expr2))
                 (if var2
                     (let ((var3 expr3))
                       (if var3 (begin body ...) #f))
                     #f))
               #f)))
        ((and-let* ((var1 expr1) (var2 expr2) (var3 expr3) (var4 expr4)) body ...)
         (let ((var1 expr1))
           (if var1
               (let ((var2 expr2))
                 (if var2
                     (let ((var3 expr3))
                       (if var3
                           (let ((var4 expr4))
                             (if var4 (begin body ...) #f))
                           #f))
                     #f))
               #f)))))))
