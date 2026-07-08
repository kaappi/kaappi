;; Regression test for #825: string-join grammar argument
(import (scheme base) (scheme write) (scheme process-context) (srfi 13) (srfi 64))

(test-begin "string-join-grammar")

;; Default delimiter is a single space
(test-equal "default delim" "one two three" (string-join '("one" "two" "three")))
(test-equal "default delim single" "hello" (string-join '("hello")))
(test-equal "default delim empty" "" (string-join '()))

;; Explicit infix grammar
(test-equal "infix" "a-b-c" (string-join '("a" "b" "c") "-" 'infix))
(test-equal "infix single" "a" (string-join '("a") "-" 'infix))
(test-equal "infix empty list" "" (string-join '() "-" 'infix))

;; strict-infix: like infix but errors on empty list
(test-equal "strict-infix" "a-b-c" (string-join '("a" "b" "c") "-" 'strict-infix))
(test-equal "strict-infix single" "a" (string-join '("a") "-" 'strict-infix))
(test-assert "strict-infix empty list errors"
  (guard (e (#t #t)) (string-join '() "-" 'strict-infix) #f))

;; prefix: delimiter before each element
(test-equal "prefix" "/usr/local/bin" (string-join '("usr" "local" "bin") "/" 'prefix))
(test-equal "prefix single" "/a" (string-join '("a") "/" 'prefix))
(test-equal "prefix empty list" "" (string-join '() "/" 'prefix))

;; suffix: delimiter after each element
(test-equal "suffix" "a;b;c;" (string-join '("a" "b" "c") ";" 'suffix))
(test-equal "suffix single" "a;" (string-join '("a") ";" 'suffix))
(test-equal "suffix empty list" "" (string-join '() ";" 'suffix))

;; Multi-char delimiter
(test-equal "multi-char infix" "a, b, c" (string-join '("a" "b" "c") ", " 'infix))
(test-equal "multi-char prefix" "::a::b" (string-join '("a" "b") "::" 'prefix))
(test-equal "multi-char suffix" "a<>b<>" (string-join '("a" "b") "<>" 'suffix))

;; Empty delimiter
(test-equal "empty delim infix" "abc" (string-join '("a" "b" "c") "" 'infix))
(test-equal "empty delim prefix" "abc" (string-join '("a" "b" "c") "" 'prefix))
(test-equal "empty delim suffix" "abc" (string-join '("a" "b" "c") "" 'suffix))

(let ((runner (test-runner-current)))
  (test-end "string-join-grammar")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
