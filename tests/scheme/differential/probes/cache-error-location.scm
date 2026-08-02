;; Regression probe for kaappi#1922 (FIXED): a cache HIT used to lose a
;; runtime error's source line and its source snippet.
;;
;; Found by this harness, tier (d).  Was a KNOWN_DIFFS entry until the fix;
;; now an ordinary probe — cold and warm must agree byte for byte, including
;; the diagnostic:
;;
;;   $ kaappi t.scm                     # cold — cache MISS, and warm — HIT
;;   t.scm:3: error[KP3004]: division by zero
;;       (display (/ 1 0))
;;
;; Mechanism.  Two location sources feed a runtime error:
;;   - `Function.line_table` — a per-instruction `line:col`, serialized into
;;     the .sbc and restored on load.  Errors located this way were always
;;     IDENTICAL cold and warm.
;;   - `toplevel_driver.vmErrorLocation`'s `fallback_line` — used when
;;     `vm.last_error_line == 0`, i.e. no line-table entry covers the failing
;;     instruction.  The fresh-compile path passes the top-level datum's
;;     line; the cache-HIT path passed a hardcoded `0`, losing the line and
;;     the snippet.  It now passes `Function.source_line`, which the compiler
;;     sets to that same datum line and the .sbc has carried since v7.
;;
;; Discriminating control: the forms in the second group below are located via
;; the line table and print an identical `file:LINE:COL:` in both runs — they
;; discriminated "the fallback_line path" from "the cache loses all debug
;; info" while the bug was live, and still pin the line-table path today.
;;
;; Nothing here may `import`: a program that imports is never cached at all
;; (docs/dev/cache.md), which would make the probe vacuous.

;; --- group 1: located by fallback_line only (the fixed divergence). -------
;; Each is guarded so the file keeps running to the end.
(display "g1") (newline)

(call-with-current-continuation
 (lambda (k)
   (with-exception-handler
    (lambda (e) (k 'caught))
    (lambda () (/ 1 0)))))

;; The uncaught one — this is the form that actually shows the divergence.
(display (/ 1 0)) (newline)

;; --- group 2: located by the line table (the control; always agreed). ----
(display "g2") (newline)
(vector-ref (vector 1 2) 9)
(string-ref "ab" 9)
(display "end") (newline)
