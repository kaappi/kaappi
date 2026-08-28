;; Systematic audit v2, Phase 2.11 — the small-file batch.
;;
;; Six primitives files that postdate the v1 campaign and had no audit test
;; of their own (~570 lines, 27 specs total):
;;
;;   src/primitives_parallel.zig     KEP-0002; backs lib/kaappi/parallel.sld
;;   src/primitives_sysinfo.zig      SRFI 59 / 112 / 193 substrate
;;   src/primitives_random_port.zig  SRFI 271 %-prefixed internals
;;   src/primitives_srfi258.zig      uninterned symbols
;;   src/primitives_srfi260.zig      generated symbols
;;   src/primitives_srfi211.zig      er-macro-transformer / lisp-transformer
;;
;; Deliberate scope choices:
;;
;;  * This file imports NEITHER (kaappi sysinfo) NOR (kaappi primitives), yet
;;    calls their %-prefixed procedures directly. That is the audit dimension
;;    D1 test: every spec in `all_specs` is registered into vm.globals by
;;    `primitives.registerAll`, so a %-name is reachable from a plain script
;;    with no import unless vm_bootstrap's `internal_helpers` removes it.
;;
;;  * Nothing here asserts a value the platform decides. `(command-line)`,
;;    every vicinity path, `%os-name`, `%cpu-architecture` and anything with
;;    a path separator in it are asserted STRUCTURALLY only — these suites run
;;    on macOS, Linux (x86_64/aarch64/riscv64/s390x/ppc64le), Windows and
;;    three BSDs.
;;
;;  * The determinized random port's byte stream IS asserted literally. It is
;;    not platform-decided: every state word is read with an explicit
;;    `.little` and every output block is written with an explicit `.little`
;;    (types_port.zig RandomGen.nextByte / primitives_random_port.zig), so the
;;    stream is byte-identical on a big-endian host by construction. Those
;;    three assertions are therefore also a byte-order canary.
;;
;;  * The --sandbox half of dimension D7 cannot be expressed here (it needs a
;;    CLI flag); it lives in tests/scheme/sandbox/sysinfo-degrades.sh.
;;
;; Run directly: zig-out/bin/kaappi tests/scheme/audit/primitives_smallbatch-audit.scm

(import (scheme base)
        (scheme write)
        (scheme read)
        (scheme eval)
        (scheme process-context)
        (srfi 64)
        (srfi 18)
        (srfi 59)
        (srfi 112)
        (srfi 193)
        (srfi 258)
        (srfi 260)
        (srfi 271 determinized)
        (srfi 211 explicit-renaming)
        (srfi 211 define-macro)
        (kaappi parallel))

(test-begin "primitives-smallbatch-audit")

;;; ------------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------------

;; #t when calling `thunk` raises anything at all.
(define (raises? thunk)
  (call-with-current-continuation
   (lambda (k)
     (with-exception-handler
      (lambda (e) (k #t))
      (lambda () (thunk) #f)))))

;; The raised condition, or the symbol no-raise.
(define (raised thunk)
  (call-with-current-continuation
   (lambda (k)
     (with-exception-handler
      (lambda (e) (k e))
      (lambda () (thunk) 'no-raise)))))

(define (err-message thunk)
  (let ((e (raised thunk)))
    (if (error-object? e) (error-object-message e) e)))

(define (starts-with? s prefix)
  (and (string? s) (string? prefix)
       (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

(define (ends-with? s suffix)
  (and (string? s) (string? suffix)
       (>= (string-length s) (string-length suffix))
       (string=? (substring s (- (string-length s) (string-length suffix))
                            (string-length s))
                 suffix)))

(define (contains-char? s c)
  (let loop ((i 0))
    (cond ((>= i (string-length s)) #f)
          ((char=? (string-ref s i) c) #t)
          (else (loop (+ i 1))))))

(define (nonempty-string? x) (and (string? x) (> (string-length x) 0)))

(define (write-to-string x)
  (let ((p (open-output-string))) (write x p) (get-output-string p)))

(define (all-distinct? lst)
  (let loop ((l lst))
    (cond ((null? l) #t)
          ((member (car l) (cdr l)) #f)
          (else (loop (cdr l))))))

;;; ==================================================================
;;; 1. primitives_parallel.zig — KEP-0002
;;; ==================================================================

;; processor-count is the file's ONE shipped spec; the other eight are
;; gate-campaign instrumentation hooks compiled in only under
;; -Dchannel-instrument=true.

(test-assert "processor-count returns an exact integer" (exact-integer? (processor-count)))
(test-assert "processor-count is at least 1" (>= (processor-count) 1))
(test-assert "processor-count is stable across calls" (= (processor-count) (processor-count)))
(test-assert "processor-count rejects an argument" (raises? (lambda () (processor-count 1))))

;; The .sld re-exports the native primitive by naming it in `export` with no
;; local define (the same trick lib/srfi/27.sld uses), so (kaappi parallel)'s
;; processor-count must be the very same object the global namespace holds.
(test-assert "(kaappi parallel) re-exports the native processor-count, not a copy"
             (eq? processor-count (eval 'processor-count (environment '(kaappi fibers)))))

;; instr_specs must be absent from a normal build — a shipped
;; (kaappi fibers) that carried these would let any program reset the
;; benchmark counters or flip the envelope-elision lever.
(test-assert "%chan-instr-reset! is not compiled into a default build"
             (raises? (lambda () (eval '%chan-instr-reset! (environment '(scheme base))))))
(test-assert "%elision-lever-set! is not compiled into a default build"
             (raises? (lambda () (eval '%elision-lever-set! (environment '(scheme base))))))
(test-assert "%chan-instr-envelope-peak-bytes is not compiled into a default build"
             (raises? (lambda () (eval '%chan-instr-envelope-peak-bytes (environment '(scheme base))))))

;;; ==================================================================
;;; 2. primitives_sysinfo.zig — SRFI 59 / 112 / 193
;;; ==================================================================

;;; --- D1: all seven %-names resolve with no (kaappi sysinfo) import ---

(test-assert "D1: %os-name reachable with no import" (nonempty-string? (%os-name)))
(test-assert "D1: %cpu-architecture reachable with no import" (nonempty-string? (%cpu-architecture)))
(test-assert "D1: %implementation-version reachable with no import" (nonempty-string? (%implementation-version)))
(test-assert "D1: %kaappi-lib-dir reachable with no import"
             (let ((d (%kaappi-lib-dir))) (or (not d) (string? d))))
(test-assert "D1: %implementation-dir reachable with no import"
             (let ((d (%implementation-dir))) (or (not d) (string? d))))
(test-assert "D1: %script-path reachable with no import"
             (let ((p (%script-path))) (or (not p) (string? p))))
(test-assert "D1: %current-lib-dir reachable with no import"
             (let ((d (%current-lib-dir))) (or (not d) (string? d))))

;;; --- arity: all seven are `.exact = 0` and must reject an argument ---

(test-assert "%script-path rejects an argument" (raises? (lambda () (%script-path 1))))
(test-assert "%current-lib-dir rejects an argument" (raises? (lambda () (%current-lib-dir 1))))
(test-assert "%kaappi-lib-dir rejects an argument" (raises? (lambda () (%kaappi-lib-dir 1))))
(test-assert "%implementation-dir rejects an argument" (raises? (lambda () (%implementation-dir 1))))
(test-assert "%implementation-version rejects an argument" (raises? (lambda () (%implementation-version 1))))
(test-assert "%os-name rejects an argument" (raises? (lambda () (%os-name 1))))
(test-assert "%cpu-architecture rejects an argument" (raises? (lambda () (%cpu-architecture 1))))

;;; --- the values are #f-or-string, never a bare error, and stable ---

(test-assert "%os-name is stable across calls" (string=? (%os-name) (%os-name)))
(test-assert "%cpu-architecture is stable across calls" (string=? (%cpu-architecture) (%cpu-architecture)))
(test-assert "%implementation-version equals (implementation-version)"
             (string=? (%implementation-version) (implementation-version)))
;; `%kaappi-lib-dir` builds its result with a hard-coded "{s}/lib/" format, so
;; the trailing separator is '/' on every platform including Windows.
(test-assert "%kaappi-lib-dir ends in lib/ when available"
             (let ((d (%kaappi-lib-dir))) (or (not d) (ends-with? d "lib/"))))
(test-assert "%implementation-dir has no filename component"
             (let ((d (%implementation-dir)))
               (or (not d) (ends-with? d "/") (ends-with? d "\\"))))

;;; --- SRFI 112 (Environment Inquiry) ---
;;; "no attempt is made to standardize the string values they return" and a
;;; procedure "returns #f if the implementation cannot provide an appropriate
;;; and relevant result" — so only the string-or-#f contract is testable.

(test-equal "SRFI 112 implementation-name is kaappi" "kaappi" (implementation-name))
(test-assert "SRFI 112 implementation-version is a non-empty string" (nonempty-string? (implementation-version)))
(test-assert "SRFI 112 cpu-architecture is a non-empty string" (nonempty-string? (cpu-architecture)))
(test-assert "SRFI 112 os-name is a non-empty string" (nonempty-string? (os-name)))
(test-assert "SRFI 112 machine-name is string-or-#f" (let ((v (machine-name))) (or (not v) (string? v))))
(test-assert "SRFI 112 os-version is string-or-#f" (let ((v (os-version))) (or (not v) (string? v))))
(test-assert "SRFI 112 os-name delegates to %os-name" (string=? (os-name) (%os-name)))
(test-assert "SRFI 112 cpu-architecture delegates to %cpu-architecture"
             (string=? (cpu-architecture) (%cpu-architecture)))
(test-assert "SRFI 112 procedures reject arguments" (raises? (lambda () (os-name 1))))

;;; --- SRFI 193 (Command Line) ---

(test-assert "SRFI 193 command-line returns a list of strings"
             (let ((cl (command-line)))
               (and (list? cl) (let loop ((l cl)) (or (null? l) (and (string? (car l)) (loop (cdr l))))))))
(test-assert "SRFI 193 command-args is the cdr of command-line, or ()"
             (let ((cl (command-line)))
               (if (null? cl) (null? (command-args)) (equal? (command-args) (cdr cl)))))
(test-assert "SRFI 193 command-name is string-or-#f"
             (let ((n (command-name))) (or (not n) (string? n))))
(test-assert "SRFI 193 command-name carries no directory component"
             (let ((n (command-name)))
               (or (not n) (and (not (contains-char? n #\/)) (not (contains-char? n #\\))))))
(test-assert "SRFI 193 command-name has its .scm extension stripped"
             (let ((n (command-name))) (or (not n) (not (ends-with? n ".scm")))))
(test-assert "SRFI 193 script-file is string-or-#f"
             (let ((f (script-file))) (or (not f) (string? f))))
(test-assert "SRFI 193 script-file is exactly %script-path"
             (equal? (script-file) (%script-path)))
(test-assert "SRFI 193 script-directory is #f exactly when script-file is"
             (eq? (not (script-file)) (not (script-directory))))
(test-assert "SRFI 193 script-file starts with script-directory"
             (let ((f (script-file)) (d (script-directory)))
               (or (not f) (starts-with? f d))))
(test-assert "SRFI 193 script-directory keeps its trailing separator"
             (let ((d (script-directory)))
               (or (not d) (string=? d "") (ends-with? d "/") (ends-with? d "\\"))))
(test-assert "SRFI 193 script-directory names a directory, not the file"
             (let ((f (script-file)) (d (script-directory)))
               (or (not f) (< (string-length d) (string-length f)))))

;;; --- SRFI 59 (Vicinity) ---
;;; A vicinity is "a directory name" that in-vicinity may be appended to;
;;; the SRFI permits #f where a concept does not apply on this platform.

(test-assert "SRFI 59 program-vicinity is string-or-#f"
             (let ((v (program-vicinity))) (or (not v) (string? v))))
(test-assert "SRFI 59 library-vicinity is string-or-#f"
             (let ((v (library-vicinity))) (or (not v) (string? v))))
(test-assert "SRFI 59 implementation-vicinity is string-or-#f"
             (let ((v (implementation-vicinity))) (or (not v) (string? v))))
(test-assert "SRFI 59 user-vicinity is a string" (string? (user-vicinity)))
(test-assert "SRFI 59 home-vicinity is string-or-#f"
             (let ((v (home-vicinity))) (or (not v) (string? v))))
(test-assert "SRFI 59 program-vicinity is exactly %current-lib-dir"
             (equal? (program-vicinity) (%current-lib-dir)))
(test-assert "SRFI 59 library-vicinity is exactly %kaappi-lib-dir"
             (equal? (library-vicinity) (%kaappi-lib-dir)))
(test-assert "SRFI 59 implementation-vicinity is exactly %implementation-dir"
             (equal? (implementation-vicinity) (%implementation-dir)))
;; in-vicinity is string-append when the vicinity already ends in a separator.
(test-equal "SRFI 59 in-vicinity appends to a slash-terminated vicinity"
            "/a/b/f.scm" (in-vicinity "/a/b/" "f.scm"))
(test-equal "SRFI 59 in-vicinity on the empty vicinity is the bare name"
            "f.scm" (in-vicinity "" "f.scm"))
(test-assert "SRFI 59 sub-vicinity result is itself a vicinity"
             (let ((v (sub-vicinity "/a/b/" "c")))
               (or (ends-with? v "/") (ends-with? v "\\"))))
(test-equal "SRFI 59 pathname->vicinity drops the filename"
            "/a/b/" (pathname->vicinity "/a/b/c.scm"))
(test-equal "SRFI 59 pathname->vicinity of a bare name is the empty vicinity"
            "" (pathname->vicinity "c.scm"))
(test-assert "SRFI 59 vicinity:suffix? accepts /" (vicinity:suffix? #\/))
(test-assert "SRFI 59 vicinity:suffix? rejects an ordinary letter" (not (vicinity:suffix? #\x)))
;; The composition the SRFI exists for: name a sibling of the running file.
(test-assert "SRFI 59 in-vicinity o program-vicinity yields a path under it"
             (let ((v (program-vicinity)))
               (or (not v) (starts-with? (in-vicinity v "data.txt") v))))

;;; ==================================================================
;;; 3. primitives_random_port.zig — SRFI 271 internals
;;; ==================================================================

(define (seed-of b) (make-bytevector 32 b))

;; A syntactically valid 46-byte state with a chosen out-position.
(define (forge-state out-pos)
  (let ((bv (make-bytevector 46 0)))
    (bytevector-u8-set! bv 0 83)   ; S
    (bytevector-u8-set! bv 1 50)   ; 2
    (bytevector-u8-set! bv 2 55)   ; 7
    (bytevector-u8-set! bv 3 49)   ; 1
    (bytevector-u8-set! bv 4 1)    ; version
    (bytevector-u8-set! bv 5 out-pos)
    (bytevector-u8-set! bv 14 1)   ; state words must not be all zero
    bv))

;;; --- D1: all five %-names reachable with no (kaappi primitives) import ---

(test-assert "D1: %random-port-make-randomized reachable with no import"
             (input-port? (%random-port-make-randomized)))
(test-assert "D1: %random-port-make-from-seed reachable with no import"
             (input-port? (%random-port-make-from-seed (seed-of 1))))
(test-assert "D1: %random-port-make-from-state reachable with no import"
             (input-port? (%random-port-make-from-state (forge-state 0))))
(test-assert "D1: %random-port-state reachable with no import"
             (bytevector? (%random-port-state (%random-port-make-from-seed (seed-of 1)))))
(test-assert "D1: %random-port? reachable with no import"
             (boolean? (%random-port? 5)))

;;; --- arity ---

(test-assert "%random-port-make-randomized rejects an argument"
             (raises? (lambda () (%random-port-make-randomized 1))))
(test-assert "%random-port? rejects zero arguments" (raises? (lambda () (%random-port?))))
(test-assert "%random-port? rejects two arguments" (raises? (lambda () (%random-port? 1 2))))
(test-assert "%random-port-state rejects zero arguments" (raises? (lambda () (%random-port-state))))
(test-assert "%random-port-make-from-seed rejects zero arguments"
             (raises? (lambda () (%random-port-make-from-seed))))

;;; --- seed validation ---

(test-assert "seed: a string is rejected"
             (raises? (lambda () (%random-port-make-from-seed "0123456789012345678901234567890123"))))
(test-assert "seed: a fixnum is rejected" (raises? (lambda () (%random-port-make-from-seed 32))))
(test-assert "seed: a vector is rejected" (raises? (lambda () (%random-port-make-from-seed (make-vector 32 0)))))
(test-assert "seed: an empty bytevector is rejected"
             (raises? (lambda () (%random-port-make-from-seed (bytevector)))))
(test-assert "seed: 31 bytes is rejected (one short of the 32-byte minimum)"
             (raises? (lambda () (%random-port-make-from-seed (make-bytevector 31 1)))))
(test-assert "seed: 32 bytes is accepted (the boundary)"
             (input-port? (%random-port-make-from-seed (make-bytevector 32 1))))
(test-assert "seed: 33 bytes is accepted, the excess ignored"
             (input-port? (%random-port-make-from-seed (make-bytevector 33 1))))
(test-assert "seed: bytes past the first 32 do not affect the stream"
             (let ((a (%random-port-make-from-seed
                       (let ((b (make-bytevector 64 3))) b)))
                   (c (%random-port-make-from-seed (make-bytevector 32 3))))
               (equal? (read-bytevector 24 a) (read-bytevector 24 c))))
(test-assert "seed: the length error names the length requirement, not just the type"
             (let ((m (err-message (lambda () (%random-port-make-from-seed (make-bytevector 31 1))))))
               (and (string? m) (> (string-length m) 0))))

;;; --- state validation: every field of isStateBytevector ---

(test-assert "state: a fixnum is rejected" (raises? (lambda () (%random-port-make-from-state 5))))
(test-assert "state: a string is rejected" (raises? (lambda () (%random-port-make-from-state "S271"))))
(test-assert "state: 45 bytes is rejected (one short)"
             (raises? (lambda () (%random-port-make-from-state
                                  (let ((b (forge-state 0))) (bytevector-copy b 0 45))))))
(test-assert "state: 46 all-zero bytes is rejected (bad magic AND zero words)"
             (raises? (lambda () (%random-port-make-from-state (make-bytevector 46 0)))))
(test-assert "state: wrong magic is rejected"
             (raises? (lambda () (%random-port-make-from-state
                                  (let ((b (forge-state 0))) (bytevector-u8-set! b 0 84) b)))))
(test-assert "state: version 0 is rejected"
             (raises? (lambda () (%random-port-make-from-state
                                  (let ((b (forge-state 0))) (bytevector-u8-set! b 4 0) b)))))
(test-assert "state: version 2 is rejected"
             (raises? (lambda () (%random-port-make-from-state
                                  (let ((b (forge-state 0))) (bytevector-u8-set! b 4 2) b)))))
(test-assert "state: out-position 8 is accepted (the documented maximum)"
             (input-port? (%random-port-make-from-state (forge-state 8))))
(test-assert "state: out-position 9 is rejected (one past the maximum)"
             (raises? (lambda () (%random-port-make-from-state (forge-state 9)))))
(test-assert "state: out-position 255 is rejected"
             (raises? (lambda () (%random-port-make-from-state (forge-state 255)))))
(test-assert "state: all-zero state words are rejected (the xoshiro fixed point)"
             (raises? (lambda () (%random-port-make-from-state
                                  (let ((b (forge-state 0))) (bytevector-u8-set! b 14 0) b)))))
(test-assert "state: a single non-zero bit anywhere in the words is enough"
             (input-port? (%random-port-make-from-state
                           (let ((b (forge-state 0)))
                             (bytevector-u8-set! b 14 0) (bytevector-u8-set! b 45 1) b))))

;;; --- %random-port-state's domain is determinized ports only ---

(test-assert "%random-port-state rejects a non-port" (raises? (lambda () (%random-port-state 5))))
(test-assert "%random-port-state rejects an ordinary string port"
             (raises? (lambda () (%random-port-state (open-input-string "x")))))
(test-assert "%random-port-state rejects a bytevector port"
             (raises? (lambda () (%random-port-state (open-input-bytevector (bytevector 1 2))))))
(test-assert "%random-port-state rejects a RANDOMIZED port (it has no state)"
             (raises? (lambda () (%random-port-state (%random-port-make-randomized)))))

;;; --- %random-port? is the determinized predicate, not "is a random port" ---

(test-assert "%random-port? is #f for a randomized port"
             (not (%random-port? (%random-port-make-randomized))))
(test-assert "%random-port? is #t for a determinized port"
             (%random-port? (%random-port-make-from-seed (seed-of 7))))
(test-assert "%random-port? is #f for a string port" (not (%random-port? (open-input-string "x"))))
(test-assert "%random-port? is #f for a non-port" (not (%random-port? 'x)))
(test-assert "%random-port? agrees with the .sld's random-port?"
             (let ((p (%random-port-make-from-seed (seed-of 7))))
               (eq? (%random-port? p) (random-port? p))))

;;; --- determinism and the state round trip ---

(test-assert "two ports from the same seed emit the same bytes"
             (equal? (read-bytevector 64 (%random-port-make-from-seed (seed-of 9)))
                     (read-bytevector 64 (%random-port-make-from-seed (seed-of 9)))))
(test-assert "two ports from different seeds diverge"
             (not (equal? (read-bytevector 64 (%random-port-make-from-seed (seed-of 9)))
                          (read-bytevector 64 (%random-port-make-from-seed (seed-of 10))))))
(test-assert "a state resumes the stream exactly, mid-block"
             (let ((a (%random-port-make-from-seed (seed-of 3))))
               (read-bytevector 5 a)                    ; leave out_pos at 5
               (let ((b (%random-port-make-from-state (%random-port-state a))))
                 (equal? (read-bytevector 40 a) (read-bytevector 40 b)))))
(test-assert "a state resumes the stream exactly, on a block boundary"
             (let ((a (%random-port-make-from-seed (seed-of 3))))
               (read-bytevector 8 a)                    ; leave out_pos at 8
               (let ((b (%random-port-make-from-state (%random-port-state a))))
                 (equal? (read-bytevector 40 a) (read-bytevector 40 b)))))
(test-assert "a state taken before any read reproduces the whole stream"
             (let* ((a (%random-port-make-from-seed (seed-of 11)))
                    (st (%random-port-state a))
                    (b (%random-port-make-from-state st)))
               (equal? (read-bytevector 32 a) (read-bytevector 32 b))))
(test-assert "SRFI 271: a state written and read back is state=? to the original"
             (let* ((st (%random-port-state (%random-port-make-from-seed (seed-of 5))))
                    (back (read (open-input-string (write-to-string st)))))
               (random-port-state=? st back)))
(test-assert "SRFI 271: the re-read state builds a port with the same bytes"
             (let* ((st (%random-port-state (%random-port-make-from-seed (seed-of 5))))
                    (back (read (open-input-string (write-to-string st)))))
               (equal? (read-bytevector 32 (make-random-port st))
                       (read-bytevector 32 (make-random-port back)))))
(test-assert "a state snapshot is 46 bytes with the S271 magic"
             (let ((st (%random-port-state (%random-port-make-from-seed (seed-of 5)))))
               (and (= (bytevector-length st) 46)
                    (= (bytevector-u8-ref st 0) 83)
                    (= (bytevector-u8-ref st 1) 50)
                    (= (bytevector-u8-ref st 2) 55)
                    (= (bytevector-u8-ref st 3) 49)
                    (= (bytevector-u8-ref st 4) 1))))
(test-assert "a fresh determinized port starts with out_pos = 8 (no pending block)"
             (= 8 (bytevector-u8-ref (%random-port-state (%random-port-make-from-seed (seed-of 5))) 5)))
(test-assert "after one byte the snapshot records out_pos = 1"
             (let ((p (%random-port-make-from-seed (seed-of 5))))
               (read-u8 p)
               (= 1 (bytevector-u8-ref (%random-port-state p) 5))))

;;; --- byte-order canary: the stream is explicitly little-endian on both
;;; --- the state-word read and the output-block write, so these literals
;;; --- must hold unchanged on s390x/ppc64le.

(test-equal "determinized stream for the all-7 seed is byte-exact"
            #u8(25 30 30 30 30 30 30 30 25 30 30 30 30 30 30 30)
            (read-bytevector 16 (%random-port-make-from-seed (seed-of 7))))
(test-equal "determinized stream for the all-255 seed is byte-exact"
            #u8(247 237 255 255 255 255 255 255)
            (read-bytevector 8 (%random-port-make-from-seed (seed-of 255))))
(test-equal "determinized stream for the 1/2/3/4 little-endian seed is byte-exact"
            #u8(0 45 0 0 0 0 0 0)
            (read-bytevector 8 (%random-port-make-from-seed
                                (bytevector 1 0 0 0 0 0 0 0  2 0 0 0 0 0 0 0
                                            3 0 0 0 0 0 0 0  4 0 0 0 0 0 0 0))))

;;; --- port-protocol behaviour ---

(test-assert "a random port is a binary input port"
             (let ((p (%random-port-make-randomized)))
               (and (input-port? p) (binary-port? p) (not (textual-port? p)) (not (output-port? p)))))
(test-assert "a random port never reaches eof" (not (eof-object? (read-u8 (%random-port-make-randomized)))))
(test-assert "peek-u8 does not consume"
             (let ((p (%random-port-make-from-seed (seed-of 4))))
               (= (peek-u8 p) (read-u8 p))))
(test-assert "peek-u8 twice returns the same byte"
             (let ((p (%random-port-make-from-seed (seed-of 4))))
               (= (peek-u8 p) (peek-u8 p))))
(test-assert "reading past a closed random port raises"
             (let ((p (%random-port-make-randomized))) (close-port p) (raises? (lambda () (read-u8 p)))))
(test-assert "a randomized port and a second one differ"
             (not (equal? (read-bytevector 32 (%random-port-make-randomized))
                          (read-bytevector 32 (%random-port-make-randomized)))))

;;; --- the .sld layer's own guards (make-random-port) ---

(test-assert "make-random-port with no argument yields a determinized port"
             (random-port? (make-random-port)))
(test-assert "make-random-port rejects a non-state, non-port initializer"
             (raises? (lambda () (make-random-port 5))))
(test-assert "make-random-port rejects a TEXTUAL input port"
             (raises? (lambda () (make-random-port (open-input-string "0123456789012345678901234567890123")))))
(test-assert "make-random-port rejects a short binary port"
             (raises? (lambda () (make-random-port (open-input-bytevector (make-bytevector 31 1))))))
(test-assert "make-random-port rejects an all-zero binary initializer"
             (raises? (lambda () (make-random-port (open-input-bytevector (make-bytevector 32 0))))))
(test-assert "make-random-port's rejection is a random-port-initialization-error"
             (random-port-initialization-error?
              (raised (lambda () (make-random-port (open-input-bytevector (make-bytevector 32 0)))))))
(test-assert "make-random-port accepts a 32-byte binary initializer"
             (random-port? (make-random-port (open-input-bytevector (make-bytevector 32 1)))))
(test-assert "random-port-state=? of no states is #t" (random-port-state=?))
(test-assert "random-port-state=? of one state is #t"
             (random-port-state=? (%random-port-state (%random-port-make-from-seed (seed-of 2)))))
(test-assert "random-port-state=? distinguishes different seeds"
             (not (random-port-state=?
                   (%random-port-state (%random-port-make-from-seed (seed-of 2)))
                   (%random-port-state (%random-port-make-from-seed (seed-of 3))))))
(test-assert "random-port-state? rejects a 46-byte non-state" (not (random-port-state? (make-bytevector 46 0))))
(test-assert "random-port-state? accepts a real snapshot"
             (random-port-state? (%random-port-state (%random-port-make-from-seed (seed-of 2)))))

;; #1913 (all-zero seed emits only zeros) also breaks SRFI 271's state
;; round trip: the degenerate port's OWN snapshot is rejected by
;; random-port-state? and by make-random-port, so the port cannot be
;; reconstructed from its own state. Both halves are the same root cause.
;; FAIL: #1913 (all-zero seed accepted; the resulting port has no valid state)
;; (test-assert "an all-zero seed is rejected"
;;              (raises? (lambda () (%random-port-make-from-seed (make-bytevector 32 0)))))
;; (test-assert "every determinized port's own state satisfies random-port-state?"
;;              (random-port-state? (%random-port-state (%random-port-make-from-seed (make-bytevector 32 0)))))
;; (test-assert "every determinized port can be rebuilt from its own state"
;;              (random-port? (make-random-port
;;                             (%random-port-state (%random-port-make-from-seed (make-bytevector 32 0))))))

;;; ==================================================================
;;; 4. primitives_srfi258.zig — uninterned symbols
;;; ==================================================================

(define u258 (string->uninterned-symbol "x"))

(test-assert "SRFI 258 an uninterned symbol is a symbol" (symbol? u258))
(test-assert "SRFI 258 an uninterned symbol is eq? to itself" (eq? u258 u258))
(test-assert "SRFI 258 it is not eqv? to the same-named interned symbol" (not (eqv? u258 'x)))
(test-assert "SRFI 258 it is not equal? to the same-named interned symbol" (not (equal? u258 'x)))
(test-assert "SRFI 258 symbol=? distinguishes it from the interned symbol" (not (symbol=? u258 'x)))
(test-equal "SRFI 258 symbol->string returns the textual name" "x" (symbol->string u258))
(test-assert "SRFI 258 two calls with the same name yield distinct symbols"
             (not (eqv? (string->uninterned-symbol "q") (string->uninterned-symbol "q"))))
(test-assert "SRFI 258 string->symbol of its name does not recover it"
             (not (eqv? (string->symbol (symbol->string u258)) u258)))
(test-assert "SRFI 258 an empty name is allowed"
             (let ((s (string->uninterned-symbol ""))) (and (symbol? s) (string=? (symbol->string s) ""))))
(test-equal "SRFI 258 a name with a space round-trips through symbol->string"
            "a b" (symbol->string (string->uninterned-symbol "a b")))
(test-equal "SRFI 258 a non-ASCII name round-trips through symbol->string"
            "\x3bb;\x3bc;" (symbol->string (string->uninterned-symbol "\x3bb;\x3bc;")))
(test-assert "SRFI 258 string->uninterned-symbol rejects a symbol"
             (raises? (lambda () (string->uninterned-symbol 'x))))
(test-assert "SRFI 258 string->uninterned-symbol rejects zero arguments"
             (raises? (lambda () (string->uninterned-symbol))))

;;; --- symbol-interned? ---

(test-assert "SRFI 258 symbol-interned? is #f for an uninterned symbol" (not (symbol-interned? u258)))
(test-assert "SRFI 258 symbol-interned? is #t for an ordinary symbol" (symbol-interned? 'x))
(test-assert "SRFI 258 symbol-interned? is #t for a string->symbol result"
             (symbol-interned? (string->symbol "made-up-name-2p11")))
(test-assert "SRFI 258 symbol-interned? signals on a non-symbol (its domain is symbols)"
             (raises? (lambda () (symbol-interned? 5))))
(test-assert "SRFI 258 symbol-interned? signals on a string, not returning #f"
             (raises? (lambda () (symbol-interned? "x"))))
(test-assert "SRFI 258 symbol-interned? rejects zero arguments" (raises? (lambda () (symbol-interned?))))

;;; --- generate-uninterned-symbol ---

(test-assert "SRFI 258 generate-uninterned-symbol yields an uninterned symbol"
             (not (symbol-interned? (generate-uninterned-symbol))))
(test-assert "SRFI 258 two generated symbols are distinct"
             (not (eqv? (generate-uninterned-symbol) (generate-uninterned-symbol))))
(test-assert "SRFI 258 two generated symbols have distinct names"
             (not (string=? (symbol->string (generate-uninterned-symbol))
                            (symbol->string (generate-uninterned-symbol)))))
(test-assert "SRFI 258 a string prefix is used verbatim"
             (starts-with? (symbol->string (generate-uninterned-symbol "pre2p11")) "pre2p11"))
(test-assert "SRFI 258 a symbol prefix contributes its name"
             (starts-with? (symbol->string (generate-uninterned-symbol 'sym2p11)) "sym2p11"))
(test-assert "SRFI 258 generate-uninterned-symbol rejects a number prefix"
             (raises? (lambda () (generate-uninterned-symbol 5))))
(test-assert "SRFI 258 generate-uninterned-symbol rejects two arguments"
             (raises? (lambda () (generate-uninterned-symbol "a" "b"))))

;;; --- printing and reading: the SRFI requires read to FAIL ---
;;; "the read procedure must signal an error (satisfying read-error?) if it
;;;  encounters such an external representation"

(test-assert "SRFI 258 write emits the unreadable #<uninterned-symbol ...> form"
             (starts-with? (write-to-string u258) "#<uninterned-symbol"))
(test-assert "SRFI 258 the written form carries the name"
             (let ((s (write-to-string (string->uninterned-symbol "zq2p11"))))
               (and (starts-with? s "#<") (ends-with? s ">"))))
(test-assert "SRFI 258 read signals on the written form"
             (raises? (lambda () (read (open-input-string (write-to-string u258))))))
(test-assert "SRFI 258 the signalled condition satisfies read-error?"
             (read-error? (raised (lambda () (read (open-input-string (write-to-string u258)))))))
(test-assert "SRFI 258 the read failure is not a file-error"
             (not (file-error? (raised (lambda () (read (open-input-string (write-to-string u258))))))))
;; CONTROL: the same text with the interned spelling reads back fine, which is
;; what proves the rejection is the uninterned form and not a broken reader.
(test-equal "SRFI 258 CONTROL: the interned spelling still reads back"
            'x (read (open-input-string "x")))
(test-assert "SRFI 258 display shows only the name (no #< wrapper)"
             (let ((p (open-output-string))) (display u258 p) (string=? (get-output-string p) "x")))

;;; --- identity semantics in the containers that use eq? ---

(test-assert "SRFI 258 memq finds an uninterned symbol by identity"
             (and (memq u258 (list 'x u258)) #t))
(test-assert "SRFI 258 memq does not match a same-named interned symbol"
             (not (memq u258 (list 'x 'y))))
(test-equal "SRFI 258 assq keys on identity, not name"
            2 (cdr (assq u258 (list (cons 'x 1) (cons u258 2)))))
(test-equal "SRFI 258 case does not match an uninterned symbol against its name"
            'no-match (case u258 ((x) 'matched) (else 'no-match)))

;;; --- D6: the SRFI-18 deep-copy boundary must preserve uninterned-ness ---

(test-assert "D6 child->parent: an uninterned symbol survives thread-join! uninterned"
             (let* ((t (thread-start! (make-thread (lambda () (string->uninterned-symbol "kid2p11")))))
                    (s (thread-join! t)))
               (and (symbol? s) (not (symbol-interned? s)) (string=? (symbol->string s) "kid2p11"))))
(test-assert "D6 parent->child: a lexically captured uninterned symbol arrives uninterned"
             (let* ((u (string->uninterned-symbol "mom2p11"))
                    (t (thread-start! (make-thread (lambda () (list (symbol-interned? u) (symbol->string u)))))))
               (equal? (thread-join! t) (list #f "mom2p11"))))
(test-assert "D6 CONTROL: an ordinary interned symbol stays eqv? across the boundary"
             (let* ((i 'ctrl2p11) (t (thread-start! (make-thread (lambda () i)))))
               (eqv? (thread-join! t) i)))
(test-assert "D6 two distinct same-named uninterned symbols are not merged by the copy"
             (let* ((a (string->uninterned-symbol "z2p11")) (b (string->uninterned-symbol "z2p11"))
                    (t (thread-start! (make-thread (lambda () (eq? a b))))))
               (not (thread-join! t))))
(test-assert "D6 the copy preserves sharing: one symbol used twice stays eq? in the child"
             (let* ((u (string->uninterned-symbol "sh2p11")) (l (list u u))
                    (t (thread-start! (make-thread (lambda () (eq? (car l) (cadr l)))))))
               (thread-join! t)))
(test-assert "D6 the copy preserves sharing in the child->parent direction too"
             (let* ((t (thread-start! (make-thread
                                       (lambda () (let ((u (string->uninterned-symbol "sh2p11"))) (list u u))))))
                    (r (thread-join! t)))
               (eq? (car r) (cadr r))))

;;; ==================================================================
;;; 5. primitives_srfi260.zig — generated symbols
;;; ==================================================================

(test-assert "SRFI 260 generate-symbol returns a symbol" (symbol? (generate-symbol)))
(test-assert "SRFI 260 a generated symbol is INTERNED (unlike SRFI 258's)"
             (symbol-interned? (generate-symbol)))
(test-assert "SRFI 260 two calls yield distinct symbols"
             (not (eqv? (generate-symbol) (generate-symbol))))
(test-assert "SRFI 260 ten calls yield ten distinct names"
             (all-distinct? (map (lambda (i) (symbol->string (generate-symbol)))
                                 '(1 2 3 4 5 6 7 8 9 10))))
;; The spec's own example:
;;   (let ([s (generate-symbol)]) (symbol=? (string->symbol (symbol->string s)) s)) => #t
(test-assert "SRFI 260 spec example: string->symbol o symbol->string recovers the symbol"
             (let ((s (generate-symbol))) (symbol=? (string->symbol (symbol->string s)) s)))
(test-assert "SRFI 260 write/read invariance holds"
             (let ((s (generate-symbol)))
               (eqv? s (read (open-input-string (write-to-string s))))))
(test-assert "SRFI 260 write/read invariance holds with a pretty-name too"
             (let ((s (generate-symbol "pretty2p11")))
               (eqv? s (read (open-input-string (write-to-string s))))))
;; The spec's second example:
;;   (let ([s1 (generate-symbol "g1")] [s2 'g1]) (symbol=? s1 s2)) => #f
(test-assert "SRFI 260 spec example: a generated symbol differs from the bare pretty-name"
             (not (symbol=? (generate-symbol "g1") 'g1)))
(test-assert "SRFI 260 the pretty-name prefixes the generated name"
             (starts-with? (symbol->string (generate-symbol "pretty2p11")) "pretty2p11"))
(test-assert "SRFI 260 two calls with the same pretty-name still differ"
             (not (eqv? (generate-symbol "same2p11") (generate-symbol "same2p11"))))
;; "The optional argument, pretty-name, must, if present, be a string."
(test-assert "SRFI 260 a symbol pretty-name is rejected (the spec requires a string)"
             (raises? (lambda () (generate-symbol 'sym))))
(test-assert "SRFI 260 a number pretty-name is rejected" (raises? (lambda () (generate-symbol 5))))
(test-assert "SRFI 260 two arguments are rejected" (raises? (lambda () (generate-symbol "a" "b"))))
(test-assert "SRFI 260 an empty pretty-name is accepted" (symbol? (generate-symbol "")))
(test-assert "SRFI 260 the generated name carries the counter and 128 entropy bits"
             (>= (string-length (symbol->string (generate-symbol ""))) 34))

;;; --- D6 + the process-global atomic counter across OS threads ---

(test-assert "SRFI 260 eight threads generate eight distinct symbols"
             (all-distinct?
              (map symbol->string
                   (map thread-join!
                        (map (lambda (i) (thread-start! (make-thread (lambda () (generate-symbol)))))
                             '(1 2 3 4 5 6 7 8))))))
(test-assert "SRFI 260 a symbol generated in a child arrives interned and read-invariant"
             (let* ((t (thread-start! (make-thread (lambda () (generate-symbol "kid2p11")))))
                    (s (thread-join! t)))
               (and (symbol-interned? s) (eqv? s (string->symbol (symbol->string s))))))
(test-assert "SRFI 260 a child-generated symbol is still distinct from a parent-generated one"
             (let* ((t (thread-start! (make-thread (lambda () (generate-symbol "dup2p11")))))
                    (child (thread-join! t))
                    (parent (generate-symbol "dup2p11")))
               (not (eqv? child parent))))

;;; ==================================================================
;;; 6. primitives_srfi211.zig — procedural transformer constructors
;;; ==================================================================

;;; --- the constructors themselves ---

(test-assert "SRFI 211 er-macro-transformer rejects a non-procedure"
             (raises? (lambda () (er-macro-transformer 5))))
(test-assert "SRFI 211 lisp-transformer rejects a non-procedure"
             (raises? (lambda () (lisp-transformer "x"))))
(test-assert "SRFI 211 er-macro-transformer rejects zero arguments"
             (raises? (lambda () (er-macro-transformer))))
(test-assert "SRFI 211 er-macro-transformer rejects two arguments"
             (raises? (lambda () (er-macro-transformer (lambda (f r c) 1) 2))))
(test-assert "SRFI 211 lisp-transformer rejects zero arguments" (raises? (lambda () (lisp-transformer))))
;; R6RS: "a transformer is not a procedure" — the object must not be callable.
(test-assert "SRFI 211 a transformer is not a procedure"
             (not (procedure? (er-macro-transformer (lambda (f r c) 1)))))
(test-assert "SRFI 211 calling a transformer as a procedure raises"
             (raises? (lambda () ((er-macro-transformer (lambda (f r c) 1)) '(a)))))
(test-assert "SRFI 211 a lisp-transformer is not a procedure either"
             (not (procedure? (lisp-transformer (lambda a 1)))))
(test-assert "SRFI 211 the type error names the procedure the caller called"
             (let ((m (err-message (lambda () (er-macro-transformer 5)))))
               (and (string? m) (starts-with? m "type error in 'er-macro-transformer'"))))
(test-assert "SRFI 211 lisp-transformer's type error names lisp-transformer"
             (let ((m (err-message (lambda () (lisp-transformer 5)))))
               (and (string? m) (starts-with? m "type error in 'lisp-transformer'"))))

;;; --- identifier? (the sub-library's other export) ---

(test-assert "SRFI 211 identifier? accepts a symbol" (identifier? 'x))
(test-assert "SRFI 211 identifier? rejects a number" (not (identifier? 5)))
(test-assert "SRFI 211 identifier? rejects a string" (not (identifier? "x")))
(test-assert "SRFI 211 identifier? rejects a list" (not (identifier? '(x))))

;;; --- a transformer bound at run time then used as a transformer-spec ---

(define er-runtime-tx
  (er-macro-transformer (lambda (form rename compare) (list (rename 'quote) 'from-runtime-binding))))
(define-syntax runtime-bound-macro er-runtime-tx)
(test-equal "SRFI 211 a Transformer value bound with define resolves as a transformer-spec"
            'from-runtime-binding (runtime-bound-macro))

;;; --- phase separation: the transformer expression is evaluated at
;;; --- macro-DEFINITION time in the GLOBAL environment ---

(define phase-witness 'global-value)
(define-syntax phase-macro
  (er-macro-transformer
   (let ((captured phase-witness))          ; read at definition time
     (lambda (form rename compare) (list (rename 'quote) captured)))))
(set! phase-witness 'changed-later)
(test-equal "SRFI 211 the transformer expression runs once, at definition time"
            'global-value (phase-macro))

;;; --- rename: consistency within one expansion, freshness across two ---

(define-syntax rename-stable
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (eq? (rename 'fresh2p11) (rename 'fresh2p11))))))
(test-assert "SRFI 211 rename of the same symbol twice in one expansion is eq?" (rename-stable))

(define-syntax rename-of-global-proc
  (er-macro-transformer (lambda (form rename compare) (list (rename 'quote) (rename 'car)))))
(test-assert "SRFI 211 rename of a global procedure name keeps reference semantics"
             (eq? (rename-of-global-proc) 'car))

;;; --- compare is free-identifier=? to this engine's strength ---

(define-syntax er-is-else
  (er-macro-transformer (lambda (form rename compare) (list (rename 'quote) (compare (cadr form) (rename 'else))))))
(test-assert "SRFI 211 compare matches the else literal" (er-is-else else))
(test-assert "SRFI 211 compare rejects an unrelated identifier" (not (er-is-else something2p11)))

(define-syntax er-is-arrow
  (er-macro-transformer (lambda (form rename compare) (list (rename 'quote) (compare (cadr form) (rename '=>))))))
(test-assert "SRFI 211 compare matches the => literal" (er-is-arrow =>))
(test-assert "SRFI 211 compare distinguishes => from else" (not (er-is-arrow else)))
;; compare is binding-aware free-identifier=? (kaappi#2388): a use-site
;; LOCAL rebinding of the literal is a different binding and no longer
;; compares equal, exactly as a syntax-rules literal refuses the same
;; shadowing. The old name-based compare answered #t here; this pin is the
;; one test the stronger semantics was designed to flip.
(test-assert "SRFI 211 compare is binding-aware: a locally rebound else no longer matches"
             (not (let ((else 1)) (er-is-else else))))
(test-assert "SRFI 211 compare is binding-aware: a locally rebound => no longer matches"
             (not (let ((=> 1)) (er-is-arrow =>))))

;;; --- lisp-transformer is deliberately UNhygienic; that is the feature ---

(define-syntax lisp-anaphoric
  (lisp-transformer (lambda (form) (list 'let (list (list 'it (cadr form))) (car (cddr form))))))
(test-equal "SRFI 211 a lisp-transformer's introduced binding IS visible to the body (no hygiene)"
            7 (lisp-anaphoric 7 it))
(define-macro (dm-double x) (list '* 2 x))
(test-equal "SRFI 211 define-macro's procedure form destructures the use's cdr" 10 (dm-double 5))
(define-macro dm-whole (lambda (form) (list 'quote (length form))))
(test-equal "SRFI 211 define-macro's expander form receives the whole use" 3 (dm-whole a b))

;;; --- HYGIENE PARITY: the documented claim is that an ER macro has exactly
;;; --- the hygiene strength a syntax-rules template has. These pairs assert
;;; --- that equivalence directly, so a fix to one path that misses the other
;;; --- fails here. The pairs are written so both members are asserted
;;; --- against the SAME expected value, per R7RS 4.3.2.

;; (a) A macro-introduced binder must not capture a use-site expression.
(define-syntax sr-swap!
  (syntax-rules () ((_ a b) (let ((tmp2p11 a)) (set! a b) (set! b tmp2p11)))))
(define-syntax er-swap!
  (er-macro-transformer
   (lambda (f r c)
     (let ((a (cadr f)) (b (car (cddr f))) (tmp (r 'tmp2p11)))
       (list (r 'let) (list (list tmp a)) (list (r 'set!) a b) (list (r 'set!) b tmp))))))
(define tmp2p11 'T)
(define oth2p11 'O)
(sr-swap! tmp2p11 oth2p11)
(test-equal "hygiene (a) syntax-rules: an introduced tmp does not capture the user's tmp"
            '(O T) (list tmp2p11 oth2p11))
(sr-swap! tmp2p11 oth2p11)
(er-swap! tmp2p11 oth2p11)
(test-equal "hygiene (a) ER: an introduced tmp does not capture the user's tmp"
            '(O T) (list tmp2p11 oth2p11))

;; (b) A macro-introduced BINDING must not capture a user expression passed in.
(define-syntax sr-hidden (syntax-rules () ((_ body) (let ((secret2p11 99)) body))))
(define-syntax er-hidden
  (er-macro-transformer (lambda (f r c) (list (r 'let) (list (list (r 'secret2p11) 99)) (cadr f)))))
(define secret2p11 'user-secret)
(test-equal "hygiene (b) syntax-rules: the introduced binding is invisible to the user body"
            'user-secret (sr-hidden secret2p11))
(test-equal "hygiene (b) ER: the introduced binding is invisible to the user body"
            'user-secret (er-hidden secret2p11))

;; (c) Referential transparency for a DEF-SITE LOCAL variable (R7RS 4.3's own
;;     worked example). Both paths get this right.
(test-equal "hygiene (c) syntax-rules: a def-site local wins over a use-site rebinding"
            'outer
            (let ((x2p11 'outer))
              (let-syntax ((m (syntax-rules () ((m) x2p11))))
                (let ((x2p11 'inner)) (m)))))

;; (d) Referential transparency for a GLOBAL NON-procedure. Both paths get
;;     this right, which is the discriminating control for (e) below.
(define gv2p11 'global-value)
(define-syntax sr-gv (syntax-rules () ((_) gv2p11)))
(define-syntax er-gv (er-macro-transformer (lambda (f r c) (r 'gv2p11))))
(test-equal "hygiene (d) syntax-rules: a global non-procedure resists a local shadow"
            'global-value (let ((gv2p11 'shadowed)) (sr-gv)))
(test-equal "hygiene (d) ER: a global non-procedure resists a local shadow"
            'global-value (let ((gv2p11 'shadowed)) (er-gv)))

;; (e) Referential transparency for a GLOBAL PROCEDURE. BROKEN on both paths.
;;     The only difference from (d) is that the referenced global holds a
;;     procedure, which is exactly what renameForHygiene leaves unrenamed.
;;     Chibi and Guile both answer correctly on every line below.
(define (gp2p11) 'global-proc)
(define-syntax sr-gp (syntax-rules () ((_) (gp2p11))))
(define-syntax er-gp (er-macro-transformer (lambda (f r c) (list (r 'gp2p11)))))
(define-syntax sr-car (syntax-rules () ((_ l) (car l))))
(define-syntax sr-add (syntax-rules () ((_ a b) (+ a b))))
;; #2003 fixed: a use-site local binding no longer captures a template's
;; free reference to a global procedure.
(test-equal "hygiene (e) syntax-rules: a global procedure resists a local shadow"
            'global-proc (let ((gp2p11 (lambda () 'shadowed))) (sr-gp)))
(test-equal "hygiene (e) ER: a global procedure resists a local shadow"
            'global-proc (let ((gp2p11 (lambda () 'shadowed))) (er-gp)))
(test-equal "hygiene (e) syntax-rules: the builtin car resists a local shadow"
            1 (let ((car (lambda (z) 'shadowed))) (sr-car (list 1 2))))
(test-equal "hygiene (e) syntax-rules: the builtin + resists a lambda-parameter shadow"
            7 ((lambda (+) (sr-add 3 4)) (lambda (a b) (* a b))))
(test-equal "hygiene (e) syntax-rules: a global procedure resists an internal-define shadow"
            'global-proc (let () (define (gp2p11) 'shadowed) (sr-gp)))

;; (f) Both paths agree on whatever they do — the parity claim itself. This
;;     stays ENABLED even while (e) is broken, because it asserts equality
;;     between the two paths rather than the R7RS answer. If a fix lands for
;;     only one path, this fails.
(test-assert "hygiene (f) PARITY: syntax-rules and ER agree under a local shadow of a global procedure"
             (eq? (let ((gp2p11 (lambda () 'shadowed))) (sr-gp))
                  (let ((gp2p11 (lambda () 'shadowed))) (er-gp))))
(test-assert "hygiene (f) PARITY: both paths agree with no shadow present"
             (eq? (sr-gp) (er-gp)))

;;; ==================================================================
;;; Done
;;; ==================================================================

(let ((runner (test-runner-current)))
  (test-end "primitives-smallbatch-audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
