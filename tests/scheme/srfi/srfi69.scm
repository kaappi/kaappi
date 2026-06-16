(import (srfi 69))
(define ht (make-hash-table))
(hash-table-set! ht 'name "kaappi")
(hash-table-set! ht 'version 1)
(display (hash-table-ref ht 'name))     ; kaappi
(newline)
(display (hash-table-size ht))          ; 2
(newline)
(display (hash-table-exists? ht 'name)) ; #t
(newline)
