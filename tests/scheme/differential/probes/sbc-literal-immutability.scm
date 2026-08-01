;; Probe / KNOWN DIVERGENCE: a cache HIT makes every literal constant mutable.
;;
;; Audit v2, Phase 4E.  Listed in run-differential.sh's KNOWN_DIFFS, so the
;; suite stays green until the fix lands; delete the entry there (and this
;; note) once it does.  Tracked as kaappi#2110.
;;
;; R7RS 4.1.2: "It is an error to alter a constant (i.e. the value of a literal
;; expression) using a mutation procedure like set-car! or string-set!."
;; Kaappi *enforces* that: `reader_datum.zig` stamps `Object.flags.immutable`
;; on every datum it reads under `mark_immutable`, and the four mutators reject
;; it with KP3002 "expected mutable <type>".
;;
;; `writeConstant`/`readConstant` carry no immutability bit, so a cache HIT
;; rebuilds every constant through the ordinary `gc.allocPair` / `allocString`
;; / `allocVectorFill` / `allocBytevector` constructors, whose `immutable`
;; defaults to false:
;;
;;   $ kaappi t.scm            # cold — cache MISS
;;   t.scm:2:1: error[KP3002]: type error in 'set-car!': expected mutable pair
;;   ...exit 1
;;
;;   $ kaappi t.scm            # warm — cache HIT
;;   (99 2)
;;   ...exit 0
;;
;; So this is not a diagnostic degradation like kaappi#1922: the program takes
;; a different branch, prints different bytes, and exits 0 instead of 1.
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
