;; Regression test for #1179: u8-ready? must return #t at EOF
;; R7RS 6.13.3: "If the port is at end of file then u8-ready? returns #t."
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "u8-ready-eof")

(test-assert "u8-ready? on empty bytevector port"
  (u8-ready? (open-input-bytevector #u8())))

(test-assert "u8-ready? after exhausting bytevector port"
  (let ((p (open-input-bytevector #u8(7))))
    (read-u8 p)
    (u8-ready? p)))

(test-assert "u8-ready? before EOF still #t"
  (u8-ready? (open-input-bytevector #u8(1 2 3))))

(let ((runner (test-runner-current)))
  (test-end "u8-ready-eof")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
