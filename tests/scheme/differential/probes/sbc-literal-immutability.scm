;; Regression probe for kaappi#2110 (FIXED): a cache HIT used to make every
;; literal constant mutable.
;;
;; Audit v2, Phase 4E.  Was a KNOWN_DIFFS entry until the fix; now an
;; ordinary probe — every mutation below must raise in BOTH runs.
;;
;; R7RS 4.1.2: "It is an error to alter a constant (i.e. the value of a literal
;; expression) using a mutation procedure like set-car! or string-set!."
;; Kaappi *enforces* that: `reader_datum.zig` stamps `Object.flags.immutable`
;; on every datum it reads under `mark_immutable`, and the four mutators reject
;; it with KP3002 "expected mutable <type>".
;;
;; `writeConstant`/`readConstant` used to carry no immutability bit, so a HIT
;; rebuilt every constant through the ordinary allocators, whose `immutable`
;; defaults to false — a `set-car!` that raised cold succeeded warm, and the
;; process exited 0 where the cold run exited 1.  Format v11 serializes the
;; bit for all four types (pair, string, vector, bytevector), so a HIT now
;; rejects exactly what a MISS rejects.
;;
;; Discriminating control: the last group builds the same shapes with `list` /
;; `string-copy` / `vector` / `bytevector` at run time.  Those are mutable in
;; BOTH runs, so the divergence is specific to the *literal* path and is not
;; "the cache loses all object flags".
;;
;; Every case is wrapped in `guard` so the file runs to the end and the
;; divergence shows up as differing stdout rather than as an early exit.

(define (try name thunk)
  (display name)
  (display " ")
  (display (guard (e (#t 'raised)) (thunk) 'mutated))
  (newline))

;; --- literals: must raise ------------------------------------------------
(define lit-pair '(1 2))
(define lit-string "abc")
(define lit-vector '#(1 2 3))
(define lit-bytevector '#u8(1 2 3))

(try "literal-pair" (lambda () (set-car! lit-pair 99)))
(try "literal-pair-cdr" (lambda () (set-cdr! lit-pair 99)))
(try "literal-string" (lambda () (string-set! lit-string 0 #\z)))
(try "literal-vector" (lambda () (vector-set! lit-vector 0 99)))
(try "literal-vector-fill" (lambda () (vector-fill! lit-vector 0)))
(try "literal-bytevector" (lambda () (bytevector-u8-set! lit-bytevector 0 99)))
(try "nested-literal-pair" (lambda () (set-car! (car '((1) 2)) 99)))
(try "literal-in-vector" (lambda () (set-car! (vector-ref '#((1 2)) 0) 99)))

;; What the values are afterwards — a second channel on the same defect.
(write (list lit-pair lit-string lit-vector lit-bytevector))
(newline)

;; --- control: run-time-built values are mutable in BOTH runs -------------
(define run-pair (list 1 2))
(define run-string (string-copy "abc"))
(define run-vector (vector 1 2 3))
(define run-bytevector (bytevector 1 2 3))

(try "runtime-pair" (lambda () (set-car! run-pair 99)))
(try "runtime-string" (lambda () (string-set! run-string 0 #\z)))
(try "runtime-vector" (lambda () (vector-set! run-vector 0 99)))
(try "runtime-bytevector" (lambda () (bytevector-u8-set! run-bytevector 0 99)))
(write (list run-pair run-string run-vector run-bytevector))
(newline)
