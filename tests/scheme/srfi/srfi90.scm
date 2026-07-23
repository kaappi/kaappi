;; SRFI-90 (extensible hash table constructor) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi90.scm
;;
;; SRFI 90 is implemented here in reduced scope (see lib/srfi/90.sld header):
;; make-table takes test/hash as ordinary positional optional arguments.
;; SRFI 89 named-argument syntax and the advisory size/min-load/max-load/
;; weak-keys/weak-values parameters are out of scope and not tested here.

(import (scheme base) (scheme process-context) (srfi 64) (srfi 69) (srfi 90))

(test-begin "srfi-90")

;;; --- (make-table): default equal? test, usable table ---
(define t1 (make-table))
(test-assert "make-table produces a hash table" (hash-table? t1))
(test-equal "new table starts empty" 0 (hash-table-size t1))

(hash-table-set! t1 'a 1)
(hash-table-set! t1 "key" 2)
(hash-table-set! t1 '(1 2) 3)
(test-equal "default test: symbol key" 1 (hash-table-ref t1 'a))
(test-equal "default test: string key" 2 (hash-table-ref t1 "key"))
(test-equal "default test: equal? list key" 3 (hash-table-ref t1 '(1 2)))
(test-equal "default table size" 3 (hash-table-size t1))

;;; --- (make-table test): custom test, hash auto-derived ---
(define t2 (make-table string=?))
(test-assert "make-table with custom test produces a hash table" (hash-table? t2))

;; Two strings that are string=? but not eq? must land in the same slot.
(define s1 (string-append "foo" "bar"))
(define s2 (string-append "foo" "bar"))
(test-assert "s1 and s2 are string=?" (string=? s1 s2))
(test-assert "s1 and s2 are not eq?" (not (eq? s1 s2)))

(hash-table-set! t2 s1 'first)
(test-equal "string=? test: lookup via a different-but-equal string object"
            'first (hash-table-ref t2 s2))

(hash-table-set! t2 s2 'second)
(test-equal "string=? test: s1/s2 share one slot" 1 (hash-table-size t2))
(test-equal "string=? test: overwrite via equivalent key" 'second (hash-table-ref t2 s1))

;;; --- (make-table test hash): both positional arguments given explicitly ---
(define t3 (make-table string=? string-hash))
(test-assert "make-table with test+hash produces a hash table" (hash-table? t3))

(define s3 (string-append "baz" "qux"))
(define s4 (string-append "baz" "qux"))
(test-assert "s3 and s4 are string=? but not eq?"
  (and (string=? s3 s4) (not (eq? s3 s4))))

(hash-table-set! t3 s3 'value)
(test-equal "explicit test+hash: lookup via equivalent-but-distinct string"
            'value (hash-table-ref t3 s4))
(test-equal "explicit test+hash: single slot for equivalent keys" 1 (hash-table-size t3))

(let ((runner (test-runner-current)))
  (test-end "srfi-90")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
