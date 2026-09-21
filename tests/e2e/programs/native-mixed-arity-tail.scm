; Guaranteed constant-stack mutual tail calls between fast entries of
; *different* arity (kaappi#2604). Every cycle in native-mutual-tail.scm is
; same-arity; this one is a 1-ary function tail-calling an 8-ary one and
; back — the shape LLVM's X86 backend refuses under tailcc on Windows. Win64
; passes four integer arguments in registers and will not *grow* a
; guaranteed tail call's stack-argument area, so thin's
; `musttail call @wide.fast(%vm, n, …seven more…, %upvalues)` — ten
; arguments, six of them on the stack, from a caller whose own prototype put
; none there — was a fatal "Can't handle guaranteed tail call under win64
; yet" from `kaappi compile`. Under the padded fastcc row every fast
; prototype is max_fast_arity wide, so the call is a sibling call into the
; caller's own argument area and compiles (docs/dev/llvm-backend.md,
; "Per-target gate"). aarch64-windows and every non-Windows host compiled
; this all along.
;
; wide does its work through a primitive the emitter does not inline (max)
; before tail-calling. That is what keeps the regression visible: `kaappi
; compile` links at -O2, where LLVM inlines a trivial 8-ary body into thin
; and the offending musttail vanishes with it — which is how the gap hid
; behind windows-x64-test, whose programs were all same-arity. A call
; through kaappi_call_scheme allocates its argument array in the block that
; makes the call, not the entry block, and LLVM's inliner never inlines a
; function with such a dynamic alloca, so the mixed-arity musttail reaches
; the backend at -O2 as it does at -O0.
;
; The 1,000,000 alternations are far past what a 1 MB (Windows default) or
; 8 MB stack holds as real frames, so a native binary that did not
; tail-call would crash rather than mismatch. And wide checks that all
; seven derived arguments — five of which travel on the stack on Win64 —
; arrived intact before recomputing the next n from them, so a call that
; dropped or shifted a stack slot derails the countdown and the parity diff
; against the interpreter catches it.
(define (thin n)
  (if (= n 0)
      'done
      (wide n (+ n 1) (+ n 2) (+ n 3) (+ n 4) (+ n 5) (+ n 6) (+ n 7))))

(define (wide p a b c d e f g)
  (if (= (+ a b c d e f g) (+ (* 7 p) 28))
      (thin (- (max a b c d e f g) 8))
      (list 'bad-arguments p a b c d e f g)))

(display (thin 1000000)) (newline)          ; done
(display (thin 5)) (newline)                ; done
(display (wide 3 4 5 6 7 8 9 10)) (newline) ; done — a consistent argument set
(display (wide 3 4 5 6 7 8 9 11)) (newline) ; (bad-arguments 3 4 5 6 7 8 9 11)
