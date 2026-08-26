;;; Audit of the `%`-prefixed internal-primitive surface (audit v2, Phase 2.1).
;;;
;;; These are registered with `primitives.INTERNAL` (in vm.globals, exported by
;;; nothing) or `primitives.INTERNAL_PUBLIC` (also exported from
;;; `(kaappi primitives)`), plus the sub-library-tagged `%` specs of SRFI
;;; 160/181/237. Every registered spec lands in vm.globals regardless of its
;;; `libs` tag -- only *export* is gated -- so all of them are callable from a
;;; plain top-level script WITH NO IMPORT AT ALL. That makes them a reachable
;;; surface which must reject bad input catchably, never panic, never corrupt
;;; state, and never blame the wrong argument.
;;;
;;; This file deliberately does NOT import (kaappi primitives) or any of the
;;; `(srfi N primitives)` sub-libraries: the no-import reachability is itself
;;; part of what is under test.
;;;
;;; Eight `.internal` specs are additionally REMOVED from vm.globals by
;;; vm_bootstrap.install (its `internal_helpers` list) because they corrupt VM
;;; state when called out of sequence. Their unreachability is asserted below.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "internal primitives audit")

;;; ------------------------------------------------------------------
;;; helpers
;;; ------------------------------------------------------------------

;; Raise-or-not, without caring about the message.
(define-syntax raises?
  (syntax-rules ()
    ((_ e ...) (guard (c (#t #t)) e ... #f))))

;; The message text of whatever `e ...` raises, or #f if it did not raise.
(define-syntax raised-message
  (syntax-rules ()
    ((_ e ...)
     (guard (c (#t (if (error-object? c) (error-object-message c) "")))
       e ... #f))))

;; Naive substring test (R7RS has none; avoids pulling in SRFI 13).
(define (has-substring? hay needle)
  (let ((hl (string-length hay)) (nl (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i nl) hl) #f)
            ((string=? (substring hay i (+ i nl)) needle) #t)
            (else (loop (+ i 1)))))))

;; Is NAME bound at top level with no import at all?
(define-syntax bound?
  (syntax-rules ()
    ((_ name) (guard (c (#t #f)) (procedure? name)))))

;; (iota-list 3) => (0 1 2). Local so the file needs no SRFI 1 import.
(define (iota-list n)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc (loop (- i 1) (cons i acc)))))

;; A field-spec list of N entries for %make-record-type-descriptor.
(define (n-field-specs n)
  (map (lambda (i) (cons (number->string i) #t)) (iota-list n)))

;;; ==================================================================
;;; D1 -- the no-import reachability surface
;;; ==================================================================
;;; Every one of these is callable from a script with no import clause.
;;; If a future change makes one unreachable, that is a real behavior
;;; change for compiler-generated code and portable .slds alike.

(test-assert "%make-record-type reachable"        (bound? %make-record-type))
(test-assert "%make-record reachable"             (bound? %make-record))
(test-assert "%record? reachable"                 (bound? %record?))
(test-assert "%record-ref reachable"              (bound? %record-ref))
(test-assert "%record-set! reachable"             (bound? %record-set!))
(test-assert "%make-promise-lazy reachable"       (bound? %make-promise-lazy))
(test-assert "%parameter-set! reachable"          (bound? %parameter-set!))
(test-assert "%parameter-convert reachable"       (bound? %parameter-convert))
(test-assert "%host-big-endian? reachable"        (bound? %host-big-endian?))
(test-assert "%default-random-source reachable"   (bound? %default-random-source))
(test-assert "%rs-next-int reachable"             (bound? %rs-next-int))
(test-assert "%rs-next-real reachable"            (bound? %rs-next-real))
(test-assert "%make-numeric-vector reachable"     (bound? %make-numeric-vector))
(test-assert "%numeric-vector? reachable"         (bound? %numeric-vector?))
(test-assert "%numeric-vector-kind reachable"     (bound? %numeric-vector-kind))
(test-assert "%numeric-vector-length reachable"   (bound? %numeric-vector-length))
(test-assert "%numeric-vector-ref reachable"      (bound? %numeric-vector-ref))
(test-assert "%numeric-vector-set! reachable"     (bound? %numeric-vector-set!))
(test-assert "%transcoded-port reachable"         (bound? %transcoded-port))
(test-assert "%random-port? reachable"            (bound? %random-port?))
(test-assert "%random-port-state reachable"       (bound? %random-port-state))
(test-assert "%make-record-type-descriptor reachable" (bound? %make-record-type-descriptor))
(test-assert "%record-rtd reachable"              (bound? %record-rtd))
(test-assert "%record-type? reachable"            (bound? %record-type?))
(test-assert "%record?/any reachable"             (bound? %record?/any))
(test-assert "%record-split-args reachable"       (bound? %record-split-args))
(test-assert "%call-with-unwind-handler reachable" (bound? %call-with-unwind-handler))
(test-assert "%unwind-raise-empty? reachable"     (bound? %unwind-raise-empty?))
(test-assert "%pop-unwind-handler! reachable"     (bound? %pop-unwind-handler!))
(test-assert "%os-name reachable"                 (bound? %os-name))

;; The 8 vm_bootstrap.internal_helpers are purged from vm.globals after
;; bootstrap capture -- they must be unreachable, not merely unexported.
;; (`%pop-wind` alone corrupts the dynamic-wind stack; the `%promise-*`
;; mutators can mark a promise forced with an arbitrary value.)
(test-assert "%push-wind purged"            (not (bound? %push-wind)))
(test-assert "%pop-wind purged"             (not (bound? %pop-wind)))
(test-assert "%promise-forced? purged"      (not (bound? %promise-forced?)))
(test-assert "%promise-forcing? purged"     (not (bound? %promise-forcing?)))
(test-assert "%promise-value purged"        (not (bound? %promise-value)))
(test-assert "%promise-complete! purged"    (not (bound? %promise-complete!)))
(test-assert "%promise-set-forcing! purged" (not (bound? %promise-set-forcing!)))
(test-assert "%promise-merge! purged"       (not (bound? %promise-merge!)))

;; The `-Dchannel-instrument=true` harness hooks must not ship in a default
;; build (they are concatenated into `specs` only under that build option).
(test-assert "%chan-instr-reset! absent by default" (not (bound? %chan-instr-reset!)))
(test-assert "%elision-lever-set! absent by default" (not (bound? %elision-lever-set!)))

;;; ==================================================================
;;; primitives.zig -- the R7RS record substrate
;;; ==================================================================

;;; --- %make-record-type ---
(test-assert "rt: valid"     (%record-type? (%make-record-type "T" 2)))
(test-assert "rt: 0 fields"  (%record-type? (%make-record-type "T" 0)))
(test-assert "rt: 255 max"   (%record-type? (%make-record-type "T" 255)))
;; arity (KP3003). 3 arguments is legal since #2088 gave the primitive an
;; optional per-field metadata list -- the same (name . mutable?) pair shape
;; %make-record-type-descriptor's field-specs use -- so "too many" starts at 4.
(test-assert "rt: too few"   (raises? (%make-record-type "T")))
(test-assert "rt: too many"  (raises? (%make-record-type "T" 2 '() 4)))
;; the optional per-field metadata list (#2088)
(test-assert "rt: field specs make an rtd"
             (%record-type? (%make-record-type "T" 2 '(("a" . #f) ("b" . #t)))))
(test-equal "rt: field specs record the names"
            '(a b)
            (%record-type-field-names (%make-record-type "T" 2 '(("a" . #f) ("b" . #t)))))
(test-assert "rt: field specs record mutability"
             (%record-field-mutable? (%make-record-type "T" 1 '(("a" . #t))) 0))
(test-assert "rt: field specs see immutability"
             (not (%record-field-mutable? (%make-record-type "T" 1 '(("a" . #f))) 0)))
(test-assert "rt: specs disagreeing with the count rejected"
             (raises? (%make-record-type "T" 2 '(("a" . #f)))))
(test-assert "rt: specs not a list rejected" (raises? (%make-record-type "T" 2 3)))
;; type, each position independently
(test-assert "rt: name not string" (raises? (%make-record-type 'T 2)))
(test-assert "rt: count not int"   (raises? (%make-record-type "T" 'x)))
(test-assert "rt: count flonum"    (raises? (%make-record-type "T" 1.5)))
;; boundary -- rejected, but see the taxonomy section for HOW
(test-assert "rt: 256 rejected"    (raises? (%make-record-type "T" 256)))
(test-assert "rt: -1 rejected"     (raises? (%make-record-type "T" -1)))

;;; --- %make-record ---
(test-assert "mr: type checked" (raises? (%make-record 5 1 2)))
(test-assert "mr: no args"      (raises? (%make-record)))
(test-equal "mr: exact field count"
            1 (let ((rt (%make-record-type "T" 2))) (%record-ref (%make-record rt 1 2) 0 rt)))
(test-equal "mr: 0-field type"
            #t (%record?/any (%make-record (%make-record-type "T" 0))))

;; %make-record does NOT check the supplied field count against
;; rt.num_fields: gc_alloc.allocRecordInstance pads short lists with
;; types.UNDEFINED and truncates long ones. The padded slot then escapes
;; into Scheme as a truthy, printable, unreadable `#<undefined>`.
;; FAIL: #1915 (%make-record ignores field-count mismatch against rt.num_fields)
;; (test-assert "mr: too few field values rejected"
;;              (raises? (%make-record (%make-record-type "T" 2) 1)))
;; FAIL: #1915 (%make-record silently drops surplus field values)
;; (test-assert "mr: too many field values rejected"
;;              (raises? (%make-record (%make-record-type "T" 2) 1 2 3)))

;; What it does today, pinned so the change is visible when it is fixed:
(test-assert "mr: short list currently pads (not raises)"
             (not (raises? (%make-record (%make-record-type "T" 2) 1))))
(test-assert "mr: surplus currently dropped (not raises)"
             (not (raises? (%make-record (%make-record-type "T" 2) 1 2 3))))

;;; --- %record? / %record-ref / %record-set! ---
(test-equal "r?: non-record is #f"
            #f (%record? 5 (%make-record-type "T" 2)))
(test-equal "r?: exact type match"
            #t (let ((rt (%make-record-type "T" 1))) (%record? (%make-record rt 9) rt)))
(test-equal "r?: distinct rtds do not match"
            #f (%record? (%make-record (%make-record-type "T" 1) 9)
                         (%make-record-type "T" 1)))
(test-assert "r?: 2nd arg type-checked" (raises? (%record? 5 5)))

(test-equal "rref: reads field"
            2 (let ((rt (%make-record-type "T" 2))) (%record-ref (%make-record rt 1 2) 1 rt)))
(test-assert "rref: index == len raises"
             (raises? (let ((rt (%make-record-type "T" 2)))
                        (%record-ref (%make-record rt 1 2) 2 rt))))
(test-assert "rref: negative index raises"
             (raises? (let ((rt (%make-record-type "T" 2)))
                        (%record-ref (%make-record rt 1 2) -1 rt))))
(test-assert "rref: index not an integer"
             (raises? (let ((rt (%make-record-type "T" 2)))
                        (%record-ref (%make-record rt 1 2) 'x rt))))
(test-assert "rref: arg0 not a record"
             (raises? (%record-ref 5 0 (%make-record-type "T" 2))))
(test-assert "rref: arg2 not a record-type"
             (raises? (let ((rt (%make-record-type "T" 2)))
                        (%record-ref (%make-record rt 1 2) 0 5))))
(test-assert "rref: wrong rtd rejected"
             (raises? (%record-ref (%make-record (%make-record-type "T" 2) 1 2)
                                   0 (%make-record-type "T" 2))))

(test-equal "rset: writes field"
            99 (let* ((rt (%make-record-type "T" 2)) (r (%make-record rt 1 2)))
                 (%record-set! r 0 99 rt) (%record-ref r 0 rt)))
(test-assert "rset: out of range raises"
             (raises? (let ((rt (%make-record-type "T" 2)))
                        (%record-set! (%make-record rt 1 2) 9 0 rt))))
(test-assert "rset: negative index raises"
             (raises? (let ((rt (%make-record-type "T" 2)))
                        (%record-set! (%make-record rt 1 2) -1 0 rt))))

;;; ==================================================================
;;; primitives_srfi237.zig -- R6RS record procedural substrate
;;; ==================================================================

(define (rtd name parent uid sealed opaque fields)
  (%make-record-type-descriptor name parent uid sealed opaque fields))

;;; --- %make-record-type-descriptor: validation, each position ---
(test-assert "mrtd: name not string" (raises? (rtd 5 #f #f #f #f '())))
(test-assert "mrtd: parent not rtd"  (raises? (rtd "T" 5 #f #f #f '())))
(test-assert "mrtd: uid not string"  (raises? (rtd "T" #f 5 #f #f '())))
(test-assert "mrtd: specs not list"  (raises? (rtd "T" #f #f #f #f 5)))
(test-assert "mrtd: improper spec list"
             (raises? (rtd "T" #f #f #f #f (cons (cons "a" #t) 5))))
(test-assert "mrtd: spec entry not a pair"
             (raises? (rtd "T" #f #f #f #f '(bad))))
(test-assert "mrtd: spec name not a string"
             (raises? (rtd "T" #f #f #f #f (list (cons 5 #t)))))
(test-assert "mrtd: sealed/opaque accept any truthy"
             (%record-type-sealed? (rtd "T" #f #f 'yes #f '())))

;;; --- inspection ---
(test-equal "mrtd: field names"
            '(a b) (%record-type-field-names (rtd "T" #f #f #f #f '(("a" . #t) ("b" . #f)))))
(test-equal "mrtd: field 0 mutable"
            #t (%record-field-mutable? (rtd "T" #f #f #f #f '(("a" . #t) ("b" . #f))) 0))
(test-equal "mrtd: field 1 immutable"
            #f (%record-field-mutable? (rtd "T" #f #f #f #f '(("a" . #t) ("b" . #f))) 1))
(test-equal "mrtd: sealed"  #t (%record-type-sealed? (rtd "T" #f #f #t #f '())))
(test-equal "mrtd: opaque"  #t (%record-type-opaque? (rtd "T" #f #f #f #t '())))
(test-equal "mrtd: generative when uid is #f"
            #t (%record-type-generative? (rtd "T" #f #f #f #f '())))
(test-equal "mrtd: not generative with uid"
            #f (%record-type-generative? (rtd "T" #f "u-gen" #f #f '())))
(test-equal "mrtd: parent of a root type is #f"
            #f (%record-type-parent (rtd "T" #f #f #f #f '())))
(test-equal "mrtd: total field count includes inherited"
            3 (%record-type-total-field-count
               (rtd "C" (rtd "P" #f #f #f #f '(("p" . #t) ("q" . #t))) #f #f #f '(("c" . #t)))))
(test-equal "mrtd: field-names is OWN fields only"
            '(c) (%record-type-field-names
                  (rtd "C" (rtd "P" #f #f #f #f '(("p" . #t))) #f #f #f '(("c" . #t)))))

;;; --- R6RS rejections, reported via argError (KP3007) with real detail ---
(test-assert "mrtd: sealed parent rejected"
             (has-substring? (raised-message (rtd "C" (rtd "P" #f #f #t #f '()) #f #f #f '()))
                             "sealed"))
(test-assert "mrtd: sealed-parent message names the parent"
             (has-substring? (raised-message (rtd "C" (rtd "P" #f #f #t #f '()) #f #f #f '()))
                             "'P'"))
(test-assert "mrtd: inherited field overflow message is specific"
             (let ((msg (raised-message
                         (rtd "C" (rtd "P" #f #f #f #f (n-field-specs 200))
                              #f #f #f (n-field-specs 100)))))
               (and (has-substring? msg "255") (has-substring? msg "inherited"))))
(test-assert "mrtd: 255 own fields is the cap"
             (= 255 (%record-type-total-field-count (rtd "T" #f #f #f #f (n-field-specs 255)))))
(test-assert "mrtd: 256 own fields rejected"
             (raises? (rtd "T" #f #f #f #f (n-field-specs 256))))

;;; --- nongenerative uid registry ---
(test-equal "mrtd: same uid + same shape reuses the rtd"
            #t (eq? (rtd "A" #f "audit-uid-same" #f #f '())
                    (rtd "A" #f "audit-uid-same" #f #f '())))
(test-assert "mrtd: same uid + different fields rejected"
             (has-substring?
              (raised-message (begin (rtd "A" #f "audit-uid-diff" #f #f '())
                                     (rtd "B" #f "audit-uid-diff" #f #f (list (cons "x" #t)))))
              "already bound"))
(test-assert "%record-uid->rtd finds a registered uid"
             (let ((t (rtd "U" #f "audit-uid-lookup" #f #f '())))
               (eq? t (%record-uid->rtd "audit-uid-lookup"))))
(test-equal "%record-uid->rtd: unknown uid is #f"
            #f (%record-uid->rtd "audit-uid-never-registered"))
(test-assert "%record-uid->rtd: non-string rejected" (raises? (%record-uid->rtd 5)))

;;; --- inheritance-aware accessors ---
(test-equal "%record?/inherit: exact type"
            #t (let ((rt (%make-record-type "T" 1))) (%record?/inherit (%make-record rt 1) rt)))
(test-equal "%record?/inherit: non-record is #f"
            #f (%record?/inherit 5 (%make-record-type "T" 1)))
(test-assert "%record?/inherit: 2nd arg type-checked" (raises? (%record?/inherit 5 5)))
(test-assert "%record-ref/inherit: out of range raises"
             (raises? (let ((rt (%make-record-type "T" 2)))
                        (%record-ref/inherit (%make-record rt 1 2) 5 rt))))
(test-assert "%record-ref/inherit: negative raises"
             (raises? (let ((rt (%make-record-type "T" 2)))
                        (%record-ref/inherit (%make-record rt 1 2) -1 rt))))
(test-assert "%record-ref/inherit: arg0 not a record"
             (raises? (%record-ref/inherit 5 0 (%make-record-type "T" 2))))
(test-assert "%record-set!/inherit: negative raises"
             (raises? (let ((rt (%make-record-type "T" 2)))
                        (%record-set!/inherit (%make-record rt 1 2) -1 9 rt))))

;;; --- %record-rtd / %record?/any / %record-type? ---
(test-equal "%record?/any: non-record" #f (%record?/any 5))
(test-equal "%record?/any: record"     #t (%record?/any (%make-record (%make-record-type "T" 1) 1)))
(test-equal "%record-type?: non-type"  #f (%record-type? 5))
(test-equal "%record-type?: type"      #t (%record-type? (%make-record-type "T" 1)))
(test-assert "%record-rtd: non-record rejected" (raises? (%record-rtd 5)))
(test-assert "%record-rtd: round-trips"
             (let* ((rt (%make-record-type "T" 1)) (r (%make-record rt 7)))
               (eq? rt (%record-rtd r))))
(test-assert "%record-type-name: non-type rejected" (raises? (%record-type-name 5)))
(test-equal "%record-type-name: symbol"
            'T (%record-type-name (%make-record-type "T" 1)))

;;; --- %record-split-args ---
(test-equal "split: suffix 2 of 4"  '((1 2) 3 4) (%record-split-args '(1 2 3 4) 2))
(test-equal "split: empty list"     '(())        (%record-split-args '() 0))
(test-equal "split: suffix 0"       '((1 2))     (%record-split-args '(1 2) 0))
(test-equal "split: whole list"     '(() 1 2)    (%record-split-args '(1 2) 2))
(test-assert "split: suffix > length raises"  (raises? (%record-split-args '(1 2) 3)))
(test-assert "split: negative suffix raises"  (raises? (%record-split-args '(1 2) -1)))
(test-assert "split: improper list rejected"  (raises? (%record-split-args '(1 . 2) 1)))
(test-assert "split: non-list rejected"       (raises? (%record-split-args 5 1)))
(test-assert "split: non-integer count"       (raises? (%record-split-args '(1 2) 'x)))
;; Hard 256-element cap (a fixed Zig stack buffer), reported as a bare
;; TypeError that dumps the whole input list into the message.
(test-assert "split: 256 elements still works"
             (= 256 (length (car (%record-split-args (iota-list 256) 0)))))
;; FAIL: #1914 (%record-split-args caps at 256 elements; reports a bare TypeError dumping the list)
;; (test-assert "split: 257 elements works"
;;              (= 257 (length (car (%record-split-args (iota-list 257) 0)))))

;;; ==================================================================
;;; primitives_srfi160.zig -- numeric vectors
;;; ==================================================================

(test-assert "nv: s8 constructed"  (%numeric-vector? (%make-numeric-vector 's8 3 0)))
(test-assert "nv: zero length"     (%numeric-vector? (%make-numeric-vector 's8 0 0)))
(test-equal "nv: kind round-trips" 's8 (%numeric-vector-kind (%make-numeric-vector 's8 3 0)))
(test-equal "nv: length"           3   (%numeric-vector-length (%make-numeric-vector 's16 3 0)))
(test-equal "nv: predicate false"  #f  (%numeric-vector? 5))

;; u8 is deliberately NOT a NumericVector kind (it stays a bytevector).
(test-assert "nv: 'u8 rejected"    (raises? (%make-numeric-vector 'u8 3 0)))
(test-assert "nv: unknown kind"    (raises? (%make-numeric-vector 'nope 3 0)))
(test-assert "nv: kind not symbol" (raises? (%make-numeric-vector "s8" 3 0)))
(test-assert "nv: length not int"  (raises? (%make-numeric-vector 's8 'x 0)))
(test-assert "nv: negative length" (raises? (%make-numeric-vector 's8 -1 0)))

;; Per-kind range enforcement at both ends.
(test-assert "nv: s8 127 ok"     (%numeric-vector? (%make-numeric-vector 's8 1 127)))
(test-assert "nv: s8 -128 ok"    (%numeric-vector? (%make-numeric-vector 's8 1 -128)))
(test-assert "nv: s8 128 out"    (raises? (%make-numeric-vector 's8 1 128)))
(test-assert "nv: s8 -129 out"   (raises? (%make-numeric-vector 's8 1 -129)))
(test-assert "nv: u16 65535 ok"  (%numeric-vector? (%make-numeric-vector 'u16 1 65535)))
(test-assert "nv: u16 65536 out" (raises? (%make-numeric-vector 'u16 1 65536)))
(test-assert "nv: u16 -1 out"    (raises? (%make-numeric-vector 'u16 1 -1)))
(test-equal "nv: u64 max round-trips"
            (- (expt 2 64) 1)
            (%numeric-vector-ref (%make-numeric-vector 'u64 1 (- (expt 2 64) 1)) 0))
(test-assert "nv: u64 2^64 out"  (raises? (%make-numeric-vector 'u64 1 (expt 2 64))))
(test-equal "nv: s64 min round-trips"
            (- (expt 2 63))
            (%numeric-vector-ref (%make-numeric-vector 's64 1 (- (expt 2 63))) 0))
(test-assert "nv: s64 2^63 out"  (raises? (%make-numeric-vector 's64 1 (expt 2 63))))
(test-assert "nv: s8 rejects flonum" (raises? (%make-numeric-vector 's8 1 1.0)))

;; Floats and complex.
(test-equal "nv: f32 fill" 1.5 (%numeric-vector-ref (%make-numeric-vector 'f32 1 1.5) 0))
(test-assert "nv: f64 accepts a rational"
             (%numeric-vector? (%make-numeric-vector 'f64 1 1/3)))
(test-equal "nv: c128 stores both parts"
            (make-rectangular 1.0 2.0)
            (let ((v (%make-numeric-vector 'c128 1 0)))
              (%numeric-vector-set! v 0 (make-rectangular 1.0 2.0))
              (%numeric-vector-ref v 0)))
(test-equal "nv: c64 stores both parts"
            (make-rectangular 1.0 2.0)
            (let ((v (%make-numeric-vector 'c64 1 0)))
              (%numeric-vector-set! v 0 (make-rectangular 1.0 2.0))
              (%numeric-vector-ref v 0)))

;; Index handling -- SRFI 160 is the reference for the whole tree here: a
;; NEGATIVE index reports as KP3006 carrying the index and the length,
;; where the record family flattens it into a bare KP3002 (see the
;; error-taxonomy section below).
(test-equal "nv: ref reads"  7 (%numeric-vector-ref (%make-numeric-vector 's8 3 7) 0))
(test-assert "nv: ref index == len"  (raises? (%numeric-vector-ref (%make-numeric-vector 's8 3 7) 3)))
(test-assert "nv: ref negative"      (raises? (%numeric-vector-ref (%make-numeric-vector 's8 3 7) -1)))
(test-assert "nv: ref on empty"      (raises? (%numeric-vector-ref (%make-numeric-vector 's8 0 0) 0)))
(test-assert "nv: ref index not int" (raises? (%numeric-vector-ref (%make-numeric-vector 's8 3 7) 'x)))
(test-assert "nv: ref arg0 checked"  (raises? (%numeric-vector-ref 5 0)))
(test-assert "nv: set! out of range" (raises? (%numeric-vector-set! (%make-numeric-vector 's8 3 0) 5 1)))
(test-assert "nv: set! negative"     (raises? (%numeric-vector-set! (%make-numeric-vector 's8 3 0) -1 1)))
(test-assert "nv: set! value range"  (raises? (%numeric-vector-set! (%make-numeric-vector 's8 3 0) 0 999)))
(test-equal "nv: set! then ref"
            5 (let ((v (%make-numeric-vector 's8 3 0))) (%numeric-vector-set! v 0 5)
                   (%numeric-vector-ref v 0)))
(test-assert "nv: length arg checked" (raises? (%numeric-vector-length 5)))
(test-assert "nv: kind arg checked"   (raises? (%numeric-vector-kind 5)))

;; A 2^46 index is a perfectly good fixnum here. The bounds check compares in
;; u64 BEFORE narrowing to usize (see primitives.fixnumIndexInBounds), so the
;; index is seen on every target -- on wasm32 (usize = u32) the pre-fix
;; `@intCast(raw_idx)` inside the check truncated it and the read silently
;; aliased an in-range element (kaappi#1912, fixed). These now pass on BOTH
;; tiers and are the %-primitive half of the cross-tier probe.
(test-assert "nv: huge index rejected (kaappi#1912)"
             (raises? (%numeric-vector-ref (%make-numeric-vector 's8 4 7) 70368744177664)))
(test-assert "nv: 2^32+1 index rejected (kaappi#1912)"
             (raises? (%numeric-vector-ref (%make-numeric-vector 's8 4 7) 4294967297)))
(test-assert "record: 2^32+1 index rejected (kaappi#1912)"
             (raises? (let ((rt (%make-record-type "R" 3)))
                        (%record-ref (%make-record rt 1 2 3) 4294967297 rt))))

;;; ==================================================================
;;; primitives_r7rs.zig -- parameter internals
;;; ==================================================================

(test-assert "%parameter-set!: non-parameter rejected"    (raises? (%parameter-set! 5 1)))
(test-assert "%parameter-convert: non-parameter rejected" (raises? (%parameter-convert 5 1)))
(test-equal "%parameter-set!: sets the value"
            42 (let ((p (make-parameter 1))) (%parameter-set! p 42) (p)))
;; Documented purpose: bypasses the converter (that is why it exists).
(test-equal "%parameter-set!: bypasses the converter"
            42 (let ((p (make-parameter 1 (lambda (x) (* x 10))))) (%parameter-set! p 42) (p)))
(test-equal "%parameter-convert: runs the converter"
            420 (let ((p (make-parameter 1 (lambda (x) (* x 10))))) (%parameter-convert p 42)))
(test-equal "%parameter-convert: identity with no converter"
            42 (let ((p (make-parameter 1))) (%parameter-convert p 42)))
;; A converter that raises must propagate catchably, not unwind natively.
(test-assert "%parameter-convert: converter error propagates"
             (raises? (%parameter-convert (make-parameter 1 (lambda (x) (error "boom"))) 42)))
(test-assert "%parameter-convert: converter arity error propagates"
             (raises? (%parameter-convert (make-parameter 1 (lambda (x y) x)) 42)))

;; Corrupting a built-in port parameter must stay catchable downstream.
(test-assert "%parameter-set! on current-output-port stays catchable"
             (raises?
              (parameterize ((current-output-port (open-output-string)))
                (%parameter-set! current-output-port 42)
                (display "x"))))

;;; --- %host-big-endian? ---
(test-assert "%host-big-endian? is a boolean"
             (boolean? (%host-big-endian?)))
(test-assert "%host-big-endian? takes no arguments"
             (raises? (%host-big-endian? 1)))

;;; ==================================================================
;;; primitives_random.zig -- SRFI 27 substrate
;;; ==================================================================

(test-assert "%default-random-source is stable"
             (eq? (%default-random-source) (%default-random-source)))
(test-assert "%rs-next-int: in range"
             (let ((n (%rs-next-int (%default-random-source) 10))) (and (<= 0 n) (< n 10))))
(test-assert "%rs-next-int: bound 0 rejected"  (raises? (%rs-next-int (%default-random-source) 0)))
(test-assert "%rs-next-int: negative rejected" (raises? (%rs-next-int (%default-random-source) -5)))
(test-assert "%rs-next-int: flonum rejected"   (raises? (%rs-next-int (%default-random-source) 1.5)))
(test-assert "%rs-next-int: symbol rejected"   (raises? (%rs-next-int (%default-random-source) 'x)))
(test-assert "%rs-next-int: arg0 checked"      (raises? (%rs-next-int 5 10)))
(test-assert "%rs-next-int: bignum bound works"
             (let ((n (%rs-next-int (%default-random-source) (expt 2 100))))
               (and (<= 0 n) (< n (expt 2 100)))))
(test-assert "%rs-next-int: negative bignum rejected"
             (raises? (%rs-next-int (%default-random-source) (- (expt 2 100)))))
(test-assert "%rs-next-real: open unit interval"
             (let ((x (%rs-next-real (%default-random-source)))) (and (< 0 x) (< x 1))))
(test-assert "%rs-next-real: arg0 checked" (raises? (%rs-next-real 5)))

;;; ==================================================================
;;; primitives_random_port.zig -- SRFI 271 substrate
;;; ==================================================================

(define (seed-of byte) (make-bytevector 32 byte))

(test-equal "%random-port?: plain value"    #f (%random-port? 5))
(test-equal "%random-port?: a randomized port is NOT determinized"
            #f (%random-port? (%random-port-make-randomized)))
(test-equal "%random-port?: a seeded port is determinized"
            #t (%random-port? (%random-port-make-from-seed (seed-of 7))))
(test-assert "%random-port-make-from-seed: non-bytevector rejected"
             (raises? (%random-port-make-from-seed 5)))
(test-assert "%random-port-make-from-seed: string is not a bytevector"
             (raises? (%random-port-make-from-seed (make-string 32 #\a))))
(test-assert "%random-port-make-from-seed: short seed rejected"
             (raises? (%random-port-make-from-seed (make-bytevector 31 7))))
(test-assert "%random-port-state: non-port rejected"  (raises? (%random-port-state 5)))
(test-assert "%random-port-state: randomized port rejected"
             (raises? (%random-port-state (%random-port-make-randomized))))
(test-equal "%random-port-state: 46-byte self-describing blob"
            46 (bytevector-length (%random-port-state (%random-port-make-from-seed (seed-of 7)))))
(test-assert "%random-port-make-from-state: round-trips its own state"
             (%random-port? (%random-port-make-from-state
                             (%random-port-state (%random-port-make-from-seed (seed-of 7))))))
(test-assert "%random-port-make-from-state: non-bytevector rejected"
             (raises? (%random-port-make-from-state 5)))
(test-assert "%random-port-make-from-state: unmagicked blob rejected"
             (raises? (%random-port-make-from-state (make-bytevector 46 0))))
(test-equal "seeded ports are reproducible"
            #t (equal? (read-bytevector 16 (%random-port-make-from-seed (seed-of 7)))
                       (read-bytevector 16 (%random-port-make-from-seed (seed-of 7)))))

;; An all-zero xoshiro256** state is a fixed point that emits only zero
;; bytes. `%random-port-make-from-state` rejects exactly that (see
;; isStateBytevector's own comment saying so), and
;; lib/srfi/271/determinized.sld raises make-random-port-initialization-error
;; for it -- but `%random-port-make-from-seed` has no such check.
;;
;; Discriminating control: the byte-identical degenerate state IS rejected
;; through the sibling entry point.
(test-assert "control: all-zero state rejected via %random-port-make-from-state"
             (raises? (%random-port-make-from-state
                       (bytevector-append (bytevector 83 50 55 49 1 0) (make-bytevector 40 0)))))
;; Discriminating control: a NON-zero seed does produce non-zero bytes, so a
;; zero result below is caused by the seed, not by the port machinery.
(test-assert "control: a non-zero seed yields non-zero bytes"
             (let ((bv (read-bytevector 16 (%random-port-make-from-seed (seed-of 7)))))
               (let loop ((i 0))
                 (cond ((= i (bytevector-length bv)) #f)
                       ((not (= 0 (bytevector-u8-ref bv i))) #t)
                       (else (loop (+ i 1)))))))
;; FAIL: #1913 (%random-port-make-from-seed accepts an all-zero seed; the port emits only zeros)
;; (test-assert "%random-port-make-from-seed rejects an all-zero seed"
;;              (raises? (%random-port-make-from-seed (seed-of 0))))

;;; ==================================================================
;;; primitives_lazy.zig -- %make-promise-lazy
;;; ==================================================================

(test-assert "%make-promise-lazy: builds a promise"
             (promise? (%make-promise-lazy (lambda () 42))))
(test-equal "%make-promise-lazy: forces its thunk"
            42 (force (%make-promise-lazy (lambda () 42))))
;; A non-procedure argument is accepted and behaves as an already-forced
;; value rather than raising. Pinned so a future tightening is visible.
(test-equal "%make-promise-lazy: non-procedure currently passes through"
            42 (force (%make-promise-lazy 42)))

;;; ==================================================================
;;; primitives_srfi181.zig -- %transcoded-port
;;; ==================================================================

(test-assert "%transcoded-port: arg0 must be a port"
             (raises? (%transcoded-port 5 'utf-8 'none 'replace)))
(test-assert "%transcoded-port: arg0 must be BINARY"
             (raises? (%transcoded-port (open-input-string "x") 'utf-8 'none 'replace)))
(test-assert "%transcoded-port: unknown codec"
             (raises? (%transcoded-port (open-input-bytevector #u8(1)) 'nope 'none 'replace)))
(test-assert "%transcoded-port: unknown eol-style"
             (raises? (%transcoded-port (open-input-bytevector #u8(1)) 'utf-8 'nope 'replace)))
(test-assert "%transcoded-port: unknown error-mode"
             (raises? (%transcoded-port (open-input-bytevector #u8(1)) 'utf-8 'none 'nope)))
(test-assert "%transcoded-port: codec must be a symbol"
             (raises? (%transcoded-port (open-input-bytevector #u8(1)) "utf-8" 'none 'replace)))
(test-equal "%transcoded-port: decodes UTF-8"
            #\h (read-char (%transcoded-port (open-input-bytevector #u8(104 105))
                                             'utf-8 'none 'replace)))

;;; ==================================================================
;;; primitives_control.zig -- SRFI 248 substrate
;;; ==================================================================

(test-assert "%call-with-unwind-handler: handler must be a procedure"
             (raises? (%call-with-unwind-handler 5 (lambda () 1))))
(test-assert "%call-with-unwind-handler: thunk must be a procedure"
             (raises? (%call-with-unwind-handler (lambda (c) 1) 5)))
(test-equal "%call-with-unwind-handler: plain return"
            7 (%call-with-unwind-handler (lambda (c) 'handled) (lambda () 7)))
(test-equal "%call-with-unwind-handler: a raise reaches the handler"
            'handled (%call-with-unwind-handler (lambda (c) 'handled)
                                                (lambda () (raise 'boom))))
(test-equal "%call-with-unwind-handler: a NATIVE error also reaches the handler"
            'handled (%call-with-unwind-handler (lambda (c) 'handled)
                                                (lambda () (car 5))))
(test-assert "%unwind-raise-empty? returns a boolean"
             (boolean? (%unwind-raise-empty?)))
;; Documented no-op when the top handler is not sticky -- it must never be
;; able to pop an ordinary handler out from under a live `guard`.
(test-equal "%pop-unwind-handler! cannot disturb an ordinary guard"
            'still-caught
            (guard (e (#t 'still-caught))
              (%pop-unwind-handler!)
              (raise 'x)))
(test-equal "%pop-unwind-handler! at top level is a no-op"
            'ok (begin (%pop-unwind-handler!) (%pop-unwind-handler!)
                       (%pop-unwind-handler!) 'ok))

;;; ==================================================================
;;; primitives_sysinfo.zig -- system inquiry (D7 sandbox gating)
;;; ==================================================================

(test-assert "%os-name is a string"                (string? (%os-name)))
(test-assert "%cpu-architecture is a string"       (string? (%cpu-architecture)))
(test-assert "%implementation-version is a string" (string? (%implementation-version)))
;; The four path-revealing ones return a string or #f; under --sandbox they
;; are not bound at all (their specs carry `.sandbox = false`). The
;; unbound-under-sandbox half is covered by tests/scheme/ sandbox suites;
;; here we only pin that they answer with a string-or-#f, never raise.
(define (string-or-false? x) (or (string? x) (not x)))
(test-assert "%script-path"          (string-or-false? (%script-path)))
(test-assert "%current-lib-dir"      (string-or-false? (%current-lib-dir)))
(test-assert "%kaappi-lib-dir"       (string-or-false? (%kaappi-lib-dir)))
(test-assert "%implementation-dir"   (string-or-false? (%implementation-dir)))
(test-assert "sysinfo: extra args rejected" (raises? (%os-name 1)))

;;; ==================================================================
;;; D2 -- error taxonomy
;;; ==================================================================
;;; typeError -> KP3002 "type error in '<proc>': expected <t>, got <v>"
;;; indexError -> KP3006 "<proc>: index <i> out of range for length <n>"
;;; argError  -> KP3007 "<proc>: <detail>"
;;;
;;; A BARE `return PrimitiveError.TypeError` is rendered by
;;; vm_calls.mapNativeError as "type error in '<proc>': got <args[0]>" --
;;; the procedure name survives, so the message looks deliberate while
;;; omitting the expected type AND naming the first argument, which in
;;; every case below is perfectly valid.

;; Positive control: a genuine wrong-type argument names the expected type.
(test-assert "taxonomy: real type error names the expectation"
             (has-substring? (raised-message (%make-record-type 'T 2)) "expected string"))
;; Positive control: an in-range-but-too-large index reports as KP3006.
(test-assert "taxonomy: positive OOB index is an index error"
             (has-substring?
              (raised-message (let ((rt (%make-record-type "T" 2)))
                                (%record-ref (%make-record rt 1 2) 2 rt)))
              "out of range for length"))
;; SRFI 160 gets the NEGATIVE case right too -- the discriminating control
;; proving the record family's behaviour below is a defect, not a
;; whole-codebase convention.
(test-assert "taxonomy: SRFI 160 negative index is an index error"
             (has-substring?
              (raised-message (%numeric-vector-ref (%make-numeric-vector 's8 3 7) -1))
              "out of range for length"))

;; The nine bare-TypeError sites. Each of these SHOULD report the offending
;; argument (an index or a count), and instead reports args[0].
;; FAIL: #1914 (negative index in %record-ref reports a bare KP3002 blaming args[0])
;; (test-assert "taxonomy: %record-ref negative index is an index error"
;;              (has-substring?
;;               (raised-message (let ((rt (%make-record-type "T" 2)))
;;                                 (%record-ref (%make-record rt 1 2) -1 rt)))
;;               "out of range for length"))
;; FAIL: #1914 (negative index in %record-set! reports a bare KP3002 blaming args[0])
;; (test-assert "taxonomy: %record-set! negative index is an index error"
;;              (has-substring?
;;               (raised-message (let ((rt (%make-record-type "T" 2)))
;;                                 (%record-set! (%make-record rt 1 2) -1 0 rt)))
;;               "out of range for length"))
;; FAIL: #1914 (negative index in %record-ref/inherit reports a bare KP3002)
;; (test-assert "taxonomy: %record-ref/inherit negative index is an index error"
;;              (has-substring?
;;               (raised-message (let ((rt (%make-record-type "T" 2)))
;;                                 (%record-ref/inherit (%make-record rt 1 2) -1 rt)))
;;               "out of range for length"))
;; FAIL: #1914 (negative index in %record-set!/inherit reports a bare KP3002)
;; (test-assert "taxonomy: %record-set!/inherit negative index is an index error"
;;              (has-substring?
;;               (raised-message (let ((rt (%make-record-type "T" 2)))
;;                                 (%record-set!/inherit (%make-record rt 1 2) -1 0 rt)))
;;               "out of range for length"))
;; FAIL: #1914 (negative index in %record-field-mutable? reports a bare KP3002)
;; (test-assert "taxonomy: %record-field-mutable? negative index is an index error"
;;              (has-substring?
;;               (raised-message (%record-field-mutable? (%make-record-type "T" 2) -1))
;;               "out of range for length"))
;; FAIL: #1914 (%make-record-type out-of-range field count blames args[0], the name string)
;; (test-assert "taxonomy: %make-record-type 256 names the count, not the name"
;;              (not (has-substring? (raised-message (%make-record-type "T" 256)) "\"T\"")))
;; FAIL: #1914 (%make-record-type negative field count blames args[0])
;; (test-assert "taxonomy: %make-record-type -1 names the count, not the name"
;;              (not (has-substring? (raised-message (%make-record-type "T" -1)) "\"T\"")))
;; FAIL: #1914 (>255 OWN fields blames args[0]; the inherited path reports argError correctly)
;; (test-assert "taxonomy: own-field overflow is as specific as the inherited one"
;;              (has-substring?
;;               (raised-message (rtd "T" #f #f #f #f
;;                                    (map (lambda (i) (cons (number->string i) #t))
;;                                         (iota-list 256))))
;;               "255"))
;; FAIL: #1914 (%record-split-args suffix > length / negative reports a bare KP3002)
;; (test-assert "taxonomy: split suffix > length is not a type error"
;;              (not (has-substring? (raised-message (%record-split-args '(1 2) 3))
;;                                   "type error")))

;;; ==================================================================
;;; D3 -- diagnostic fidelity
;;; ==================================================================
;;; #1899 (heap values rendering opaquely as `#<symbol>` etc.) was fixed
;;; separately; its regression coverage lives in
;;; tests/scheme/audit/error-taxonomy-audit.scm and
;;; tests/scheme/errors/type-error-value-identity-1899.sh, not here. These two
;;; are distinct from it.
;;;
;;; All three defects below were found by this audit and fixed in #1916; the
;;; assertions are kept alongside their original controls, which is what makes
;;; each one discriminating (every control passed before the fix too).

;; An integral flonum must keep its `.0`, or "expected exact integer, got 1"
;; argues against itself -- 1 *is* an exact integer. Control: 1.5 always
;; rendered correctly as "1.5", so a `{d}`-vs-printer regression shows up here
;; and not in the control.
(test-assert "diagnostic control: 1.5 renders as 1.5"
             (has-substring? (raised-message (%make-record-type "T" 1.5)) "1.5"))
;; Stated positively, not as `(not (has-substring? ... "got 1"))`: "got 1" is a
;; PREFIX of the correct "got 1.0", so the negative form cannot pass whatever
;; the code does. The positive form is fully discriminating anyway -- the buggy
;; message was exactly "got 1", which does not contain "got 1.0".
(test-assert "diagnostic: 1.0 renders as 1.0, not as an exact 1"
             (has-substring? (raised-message (%make-record-type "T" 1.0)) "got 1.0"))

;; A multi-limb bignum out of an element kind's range must be reported as out
;; of RANGE, not as the wrong TYPE -- it is an exact integer. Control: a
;; single-limb out-of-range value already got the "in-range" wording.
(test-assert "diagnostic control: 65536 for u16 says in-range"
             (has-substring? (raised-message (%make-numeric-vector 'u16 1 65536))
                             "in-range"))
(test-assert "diagnostic: 2^64 for u16 also says in-range"
             (has-substring? (raised-message (%make-numeric-vector 'u16 1 (expt 2 64)))
                             "in-range"))
(test-assert "diagnostic: 2^64 for s8 says in-range"
             (has-substring? (raised-message (%make-numeric-vector 's8 1 (expt 2 64)))
                             "in-range"))
;; A NEGATIVE multi-limb bignum into an unsigned kind is rejected for its sign,
;; not its width -- the same wording a negative fixnum gets, which is the
;; control here.
(test-assert "diagnostic control: -1 for u16 says non-negative"
             (has-substring? (raised-message (%make-numeric-vector 'u16 1 -1))
                             "non-negative"))
(test-assert "diagnostic: -2^64 for u16 also says non-negative"
             (has-substring? (raised-message (%make-numeric-vector 'u16 1 (- (expt 2 64))))
                             "non-negative"))
;; The distinction only means something if a genuine non-integer still reports
;; as one -- otherwise "in-range" everywhere would pass the assertions above.
(test-assert "diagnostic: a string still says exact integer"
             (has-substring? (raised-message (%make-numeric-vector 'u16 1 "x"))
                             "exact integer"))

;;; The procedure name a `%` primitive reports must match the name that was
;;; called -- otherwise the message points at a DIFFERENT, real procedure
;;; (`record?` is exported by (srfi 237); `transcoded-port` by (srfi 181)).
;;; Asserting the bare name is absent is what discriminates: "%record?"
;;; contains "record?", so the presence check alone would pass either way.
(test-assert "name drift: %record? reports as %record?"
             (has-substring? (raised-message (%record? 5 5)) "%record?"))
(test-assert "name drift: %record? does not report as bare record?"
             (not (has-substring? (raised-message (%record? 5 5)) "'record?")))
(test-assert "name drift: %transcoded-port reports as %transcoded-port"
             (has-substring? (raised-message (%transcoded-port 5 'utf-8 'none 'replace))
                             "%transcoded-port"))
(test-assert "name drift: %transcoded-port does not report as bare transcoded-port"
             (not (has-substring? (raised-message (%transcoded-port 5 'utf-8 'none 'replace))
                                  "'transcoded-port")))

;;; ==================================================================
;;; D4 -- registration-table invariant
;;; ==================================================================
;;; Every `%` spec's declared arity equals (highest args[N] indexed) + 1;
;;; no body reads past its declared arity. Verified statically against
;;; src/primitives*.zig. The runtime half is that every one of them
;;; enforces its arity as KP3003 rather than reading undefined memory.

(test-assert "arity: %record-ref rejects 2 args"   (raises? (%record-ref 1 2)))
(test-assert "arity: %record-ref rejects 4 args"
             (raises? (%record-ref 1 2 3 4)))
(test-assert "arity: %numeric-vector-set! rejects 2 args"
             (raises? (%numeric-vector-set! (%make-numeric-vector 's8 1 0) 0)))
(test-assert "arity: %transcoded-port rejects 3 args"
             (raises? (%transcoded-port (open-input-bytevector #u8(1)) 'utf-8 'none)))
(test-assert "arity: %make-record-type-descriptor rejects 5 args"
             (raises? (%make-record-type-descriptor "T" #f #f #f #f)))
(test-assert "arity: %default-random-source rejects 1 arg"
             (raises? (%default-random-source 1)))
(test-assert "arity: %record-split-args rejects 1 arg"
             (raises? (%record-split-args '(1 2))))

(let ((runner (test-runner-current)))
  (test-end "internal primitives audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
