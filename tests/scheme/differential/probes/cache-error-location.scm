;; Probe / KNOWN DIVERGENCE: a cache HIT loses a runtime error's source line
;; and its source snippet.
;;
;; Found by this harness, tier (d).  Listed in run-differential.sh's
;; KNOWN_DIFFS, so the suite stays green until the fix lands; delete the entry
;; there (and this note) once it does.
;;
;;   $ kaappi t.scm                     # cold — cache MISS
;;   t.scm:3: error[KP3004]: division by zero
;;       (display (/ 1 0))
;;
;;   $ kaappi t.scm                     # warm — cache HIT
;;   t.scm: error[KP3004]: division by zero
;;
;; Exit code and stdout agree; only the diagnostic degrades.  This contradicts
;; docs/dev/cache.md, whose whole premise is that the cache is transparent and
;; that an invisible cache is a hazard (kaappi#1516).
;;
;; Mechanism.  Two location sources feed a runtime error:
;;   - `Function.line_table` — a per-instruction `line:col`, serialized into
;;     the .sbc and restored on load.  Errors located this way are IDENTICAL
;;     cold and warm.
;;   - `toplevel_driver.vmErrorLocation`'s `fallback_line` — used when
;;     `vm.last_error_line == 0`, i.e. no line-table entry covers the failing
;;     instruction.  The fresh-compile path (src/main.zig:815) passes the
;;     top-level datum's line, so the error prints `file:LINE:` (line, no
;;     column) plus the snippet.  The cache-HIT path (src/main.zig:732)
;;     passes a hardcoded `0`, so both are lost.
;;
;; Discriminating control: the forms in the second group below are located via
;; the line table and print an identical `file:LINE:COL:` in BOTH runs.  So
;; this is not "the cache loses all debug info" — it is exactly the
;; fallback_line path.  `--no-ir-opt` (which bypasses the cache in both
;; directions) also matches the cold run, and `kaappi cache clear` restores it,
;; which is what makes the cache — not the optimiser — the responsible tier.
;;
;; Nothing here may `import`: a program that imports is never cached at all
;; (docs/dev/cache.md), which would make the probe vacuous.

;; --- group 1: located by fallback_line only.  These DIVERGE. --------------
;; Each is guarded so the file keeps running to the end.
(display "g1") (newline)

(call-with-current-continuation
 (lambda (k)
   (with-exception-handler
    (lambda (e) (k 'caught))
    (lambda () (/ 1 0)))))

;; The uncaught one — this is the form that actually shows the divergence.
(display (/ 1 0)) (newline)

;; --- group 2: located by the line table.  These AGREE (the control). -----
(display "g2") (newline)
(vector-ref (vector 1 2) 9)
(string-ref "ab" 9)
(display "end") (newline)
