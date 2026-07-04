;; Regression test for #1013: current-input-port parameter corrupted
;; under extreme GC pressure. The port objects were not rooted between
;; successive allocPort calls in VM.init, so GC could collect stdin
;; before stdout was allocated.
;;
;; Run with: zig build -Dgc-threshold=1 run -- tests/scheme/smoke/port-param-gc-1013.scm

(import (scheme base) (scheme write))

(define (assert-true msg v)
  (unless v
    (display "FAIL: ") (display msg) (newline)
    (error "assertion failed" msg)))

(assert-true "current-input-port is an input port"
  (input-port? (current-input-port)))

(assert-true "current-output-port is an output port"
  (output-port? (current-output-port)))

(assert-true "current-error-port is an output port"
  (output-port? (current-error-port)))

(display "port-param-gc-1013: PASS") (newline)
