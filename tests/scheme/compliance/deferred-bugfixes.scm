(import (scheme base) (scheme write) (scheme read) (scheme char) (scheme file)
        (srfi 27) (srfi 69))
(import (scheme process-context) (srfi 64))

(test-begin "deferred bugfixes")

;;; Bug 1: write-bytevector start/end
(let ((p (open-output-bytevector)))
  (write-bytevector #u8(10 20 30 40 50) p 1 4)
  (test-equal #u8(20 30 40) (get-output-bytevector p)))
(let ((p (open-output-bytevector)))
  (write-bytevector #u8(1 2 3) p)
  (test-equal #u8(1 2 3) (get-output-bytevector p)))
(let ((p (open-output-bytevector)))
  (write-bytevector #u8(1 2 3 4 5) p 3)
  (test-equal #u8(4 5) (get-output-bytevector p)))

;;; Bug 2: textual-port? on binary ports
(test-equal #t (textual-port? (open-input-string "hello")))
(test-equal #t (textual-port? (open-output-string)))
(call-with-output-file "/tmp/kaappi-deferred-test.bin"
  (lambda (p) (display "x" p)))
(let ((p (open-binary-input-file "/tmp/kaappi-deferred-test.bin")))
  (test-equal #f (textual-port? p))
  (test-equal #t (binary-port? p))
  (close-port p))
(delete-file "/tmp/kaappi-deferred-test.bin")

;;; Bug 3: random-source-state roundtrip
(let ((rs (make-random-source)))
  (random-source-pseudo-randomize! rs 42 0)
  (let ((gen (random-source-make-integers rs)))
    (gen 1000)
    (let ((state (random-source-state-ref rs)))
      ;; State is a list of 4 fixnums
      (test-equal #t (list? state))
      (test-equal 4 (length state))
      ;; Generate a value, restore, verify same first value
      (let ((v2 (gen 1000)))
        (random-source-state-set! rs state)
        (test-equal v2 (gen 1000))))))

;;; Bug 4: interaction-environment not #t
(test-equal #t (not (eq? (interaction-environment) #t)))

;;; Bug 5: ffi-open error message
(import (srfi 13))
(test-equal #t (guard (e (#t (and (error-object? e)
                                  (number? (string-contains (error-object-message e) "ffi-open")))))
                 (ffi-open "nonexistent-library-zzzzz")
                 #f))

;;; Bug 6: ffi-fn error message
(let ((lib (ffi-open #f)))
  (test-equal #t (guard (e (#t (and (error-object? e)
                                    (number? (string-contains (error-object-message e) "ffi-fn")))))
                   (ffi-fn lib "nonexistent_symbol_zzzzz" '(int) 'int)
                   #f))
  (ffi-close lib))

;;; Bug 7: string-ci-hash Unicode
;; Same-case strings should hash identically
(test-equal #t (= (string-ci-hash "hello") (string-ci-hash "HELLO")))
(test-equal #t (= (string-ci-hash "abc") (string-ci-hash "ABC")))
;; Mixed case
(test-equal #t (= (string-ci-hash "Hello") (string-ci-hash "hELLO")))

;;; Bug 8: load raises file-error
(test-equal #t (guard (e (#t (file-error? e)))
                 (load "/nonexistent-file-kaappi-test.scm")
                 #f))

(let ((runner (test-runner-current)))
  (test-end "deferred bugfixes")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
