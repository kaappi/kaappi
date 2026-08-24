;;; Fixture for tests/wasm/library-load.scm — a file-backed .sld that is
;;; reachable only through the script's own directory being on vm.lib_paths.
;;; There is deliberately no copy under lib/, so the built-in "" and "lib/"
;;; prefixes cannot resolve it (kaappi#2109).
(define-library (wasm-fixtures sibling)
  (import (scheme base))
  (export sibling-value)
  (begin
    (define sibling-value 'from-sibling-sld)))
