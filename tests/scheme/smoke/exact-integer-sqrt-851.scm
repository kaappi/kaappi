;; Regression test for #851: exact-integer-sqrt hangs on large bignums.

;; These should complete instantly, not hang
(let-values (((s r) (exact-integer-sqrt (expt 2 1100))))
  (display (= (+ (* s s) r) (expt 2 1100)))
  (newline))

(let-values (((s r) (exact-integer-sqrt (expt 2 3000))))
  (display (= (+ (* s s) r) (expt 2 3000)))
  (newline))
