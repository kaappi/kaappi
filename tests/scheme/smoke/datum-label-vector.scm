;; Regression test for #1213: datum-label references inside vectors not patched
(import (scheme base) (scheme read) (scheme write) (scheme process-context) (srfi 64))

(test-begin "datum-label-vector")

;; Direct self-reference in vector
(let ((v (read (open-input-string "#0=#(1 #0#)"))))
  (test-equal "vector slot 0" 1 (vector-ref v 0))
  (test-assert "vector self-ref" (eq? v (vector-ref v 1))))

;; Reference nested in a pair inside the vector
(let ((v (read (open-input-string "#0=#((#0#) 2)"))))
  (test-assert "ref nested in pair inside vector"
    (eq? v (car (vector-ref v 0)))))

;; Multiple self-references in vector
(let ((v (read (open-input-string "#0=#(#0# #0# #0#)"))))
  (test-assert "all slots self-ref"
    (and (eq? v (vector-ref v 0))
         (eq? v (vector-ref v 1))
         (eq? v (vector-ref v 2)))))

;; Cyclic list still works (existing behavior)
(let ((c (read (open-input-string "#0=(1 #0# 2)"))))
  (test-assert "list self-ref" (eq? c (cadr c))))

;; Vector ref inside list (pair case — placeholder IS the result)
(let ((l (read (open-input-string "#0=(1 #(#0#) 3)"))))
  (test-assert "vector-in-list ref"
    (eq? l (vector-ref (cadr l) 0))))

(let ((runner (test-runner-current)))
  (test-end "datum-label-vector")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
