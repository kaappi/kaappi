;; Regression test for #425: (scheme write) should only export
;; display, write, write-shared, write-simple per R7RS

(import (scheme base))

;; Verify newline, write-char, write-string come from (scheme base)
(import (only (scheme base) newline write-char write-string))

;; Verify (scheme write) has exactly the R7RS set
(import (only (scheme write) display write write-shared write-simple))

(display "PASS")
(newline)
