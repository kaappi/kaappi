;; Regression test for #1166: take-right/drop-right reject dotted lists
(import (scheme base) (scheme write) (scheme process-context) (srfi 1) (srfi 64))

(test-begin "srfi1-take-drop-right-dotted")

;; SRFI-1 spec examples for dotted lists
(test-equal "take-right dotted k=2" '(2 3 . d) (take-right '(1 2 3 . d) 2))
(test-equal "take-right dotted k=0" 'd (take-right '(1 2 3 . d) 0))
(test-equal "drop-right dotted k=2" '(1) (drop-right '(1 2 3 . d) 2))
(test-equal "drop-right dotted k=0" '(1 2 3) (drop-right '(1 2 3 . d) 0))

;; Proper lists still work
(test-equal "take-right proper" '(4 5) (take-right '(1 2 3 4 5) 2))
(test-equal "drop-right proper" '(1 2 3) (drop-right '(1 2 3 4 5) 2))
(test-equal "take-right all" '(1 2 3) (take-right '(1 2 3) 3))
(test-equal "drop-right all" '() (drop-right '(1 2 3) 3))
(test-equal "take-right none" '() (take-right '(1 2 3) 0))
(test-equal "drop-right none" '(1 2 3) (drop-right '(1 2 3) 0))

(let ((runner (test-runner-current)))
  (test-end "srfi1-take-drop-right-dotted")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
