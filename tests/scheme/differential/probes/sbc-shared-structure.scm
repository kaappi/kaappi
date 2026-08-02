;; Regression probe for kaappi#2111 (FIXED): a cache HIT used to unshare
;; datum-label structure.
;;
;; Audit v2, Phase 4E.  Was a KNOWN_DIFFS entry until the fix; now an
;; ordinary probe — every eq? below answers the same in BOTH runs.
;;
;; R7RS 2.4 (Datum labels): "#<n>= <datum> reads as <datum>, but also results
;; in <datum> being labelled by <n>.  #<n># serves as a reference to some
;; object labelled by #<n>=; the result is the same object as the #<n>= label."
;; The reader honours that — `reader_datum.zig` patches every reference to the
;; one labelled object — so cold, `(eq? (car v) (cadr v))` on `'(#1=(1 2) #1#)`
;; is #t.
;;
;; `writeConstant` was a plain recursive walk with no visited-set, so it
;; emitted the labelled datum once per *reference*, and `readConstant`
;; allocated a fresh object for each — a HIT answered #f where the cold run
;; answered #t.  Format v11 emits every already-seen pair/string/vector/
;; bytevector as a TAG_BACKREF to its first occurrence, so sharing (and
;; therefore eq?) round-trips.
;;
;; Discriminating control: the last group writes the same shape WITHOUT a
;; label.  Cold already answers #f there, and warm agrees — so this is sharing
;; being lost, not `eq?` behaving differently after a HIT.
;;
;; Same root cause, two more former symptoms, both also closed by the
;; back-reference encoding:
;;
;;   - a CYCLIC literal (`'#0=(1 . #0#)`) used to recurse to the depth guard
;;     and write an entry the reader rejected — a permanent MISS.  It now
;;     terminates and HITs; sbc-constant-depth.scm probes it.
;;   - a shared DAG made the .sbc exponential in the source (labels nested
;;     `#k=(#k-1# #k-1#)` 20 deep were 241 source bytes and 4.7 MB of .sbc);
;;     each level is now emitted once, so the entry stays linear (~474 B).

(define shared-pair '(#1=(1 2) #1#))
(define shared-vector '#(#2=(a) #2# #2#))
(define shared-string '(#3="abc" #3#))
(define shared-deep '(#4=(1 2) (x #4#) #(#4#)))

(display (list 'pair (eq? (car shared-pair) (cadr shared-pair))))
(newline)
(display (list 'vector
               (eq? (vector-ref shared-vector 0) (vector-ref shared-vector 1))
               (eq? (vector-ref shared-vector 1) (vector-ref shared-vector 2))))
(newline)
(display (list 'string (eq? (car shared-string) (cadr shared-string))))
(newline)
(display (list 'deep
               (eq? (car shared-deep) (cadr (cadr shared-deep)))
               (eq? (car shared-deep) (vector-ref (caddr shared-deep) 0))))
(newline)

;; `write-shared` is the printer's own view of the same question.
(write-shared shared-pair)
(newline)

;; --- control: the same shape with no label -------------------------------
(define unshared-pair '((1 2) (1 2)))
(display (list 'control (eq? (car unshared-pair) (cadr unshared-pair))))
(newline)
