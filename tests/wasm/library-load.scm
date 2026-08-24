;;; Kaappi WASM file-backed library loading test.
;;;
;;; Regression test for kaappi#2108 and the vm.lib_paths half of #2109.
;;;
;;; #2108: platform.openRead had no WASI branch, so resolveLibraryPath's
;;; existence probe failed for every candidate path and no file-backed .sld
;;; was importable on wasm32 even when the host mounted the directory. (srfi 2)
;;; lives at lib/srfi/2.sld — a portable .sld, not a registry built-in — so its
;;; import only succeeds when the resolver can actually open files through the
;;; preopened directory.
;;;
;;; #2109: main.zig's WASM entry returned before vm.lib_paths was populated, so
;;; a .sld beside the program was invisible. (wasm-fixtures sibling) lives in a
;;; subdirectory next to this script (tests/wasm/wasm-fixtures/sibling.sld) and
;;; is reachable only through the script-directory entry in vm.lib_paths.
;;;
;;; Any FAIL line fails CI.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 2)
        (wasm-fixtures sibling))

(define failures 0)
(define (check label ok)
  (display (if ok "PASS " "FAIL "))
  (display label)
  (newline)
  (if (not ok) (set! failures (+ failures 1))))

(check "file-backed .sld loads through the preopened directory"
       (equal? (and-let* ((x 1) (y 2)) (+ x y)) 3))
(check "and-let* short-circuits on #f"
       (eq? (and-let* ((x #f)) x) #f))
(check "sibling .sld resolves through the script-directory lib path"
       (eq? sibling-value 'from-sibling-sld))

(if (> failures 0)
    (begin (display "LIBRARY LOAD TESTS FAILED") (newline) (exit 1))
    (begin (display "all library load tests passed") (newline)))
