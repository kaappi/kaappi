;;; SRFI 42 — Eager Comprehensions
;;;
;;; Direct-style port: each qualifier expands to a loop nested around the
;;; rest of the comprehension, with a mutable stop flag (s) threaded
;;; through for :while/:until early exit.  This differs from the
;;; reference implementation's CPS design (everything reduced to a :do
;;; form), so the generic dispatching layer (: / :dispatched /
;;; :generator-proc) uses the SRFI's *runtime* generator-procedure
;;; protocol instead of :do fusion: a generator procedure g is called as
;;; (g empty) and returns the next value of its sequence, or the
;;; eq?-unique sentinel `empty' once exhausted — exactly the protocol
;;; the :dispatched spec text defines.  :generator-proc compiles the
;;; standard typed generators straight to closure constructors (%gen-*);
;;; any other generator form falls back to a call/cc coroutine over
;;; do-ec, which therefore shares the engine's general continuation
;;; limits (stepping a coroutine-backed generator after the native frame
;;; it was created under has returned is unsupported; the standard types
;;; never touch call/cc).
;;;
;;; Deliberate deviations from the reference implementation:
;;;   - The (index i) variable form is not supported (in any generator —
;;;     as before this port never had it).
;;;   - A bare (:while <expr>) / (:until <expr>) qualifier — not part of
;;;     the spec's grammar, kept from the original port — stops the
;;;     WHOLE comprehension.  The spec's (:while <generator> <expr>)
;;;     wrapping form scopes the test to the wrapped generator only, as
;;;     the spec requires.
;;;   - :parallel sub-generators must be plain single-variable generator
;;;     forms (typed generators, :, :dispatched, :let, ...); raw :do
;;;     forms and :while/:until-wrapped generators are rejected at
;;;     expansion time rather than merged.
;;;   - The reference's make-initial-:-dispatch tests (string? a1) twice
;;;     in its 2- and 3-argument string cases where a2/a3 were meant —
;;;     corrected here.
;;;   - A zero step is rejected loudly in :real-range too, not just in
;;;     :range (where the reference already rejects it).  The reference's
;;;     :real-range instead raises division-by-zero for an exact zero
;;;     step and loops forever on an inexact one (istop = +inf.0);
;;;     silent non-termination is the failure mode worth closing.
;;;   - :parallel steps every sub-generator once per iteration and stops
;;;     at the first exhausted one, so longer generators are advanced one
;;;     step past the shortest — the same one-step-ahead the reference's
;;;     fused loops perform.
(define-library (srfi 42)
  (import (scheme base)
          (scheme cxr)
          (scheme read))
  (export list-ec string-ec vector-ec
          append-ec sum-ec product-ec
          min-ec max-ec
          first-ec last-ec any?-ec every?-ec
          do-ec fold-ec fold3-ec
          : :list :string :vector :range :real-range :char-range
          :integers :port :do :let :parallel :while :until
          :dispatched :generator-proc
          :-dispatch-ref :-dispatch-set!
          make-initial-:-dispatch dispatch-union)
  (begin

    ;; Generator keywords — error when used outside a comprehension.
    ;; Defined first so %do-ec can resolve them as syntax-rules literals.
    (define-syntax :
      (syntax-rules ()
        ((_ rest ...) (error ": used outside a comprehension"))))
    (define-syntax :list
      (syntax-rules ()
        ((_ rest ...) (error ":list used outside a comprehension"))))
    (define-syntax :string
      (syntax-rules ()
        ((_ rest ...) (error ":string used outside a comprehension"))))
    (define-syntax :vector
      (syntax-rules ()
        ((_ rest ...) (error ":vector used outside a comprehension"))))
    (define-syntax :range
      (syntax-rules ()
        ((_ rest ...) (error ":range used outside a comprehension"))))
    (define-syntax :real-range
      (syntax-rules ()
        ((_ rest ...) (error ":real-range used outside a comprehension"))))
    (define-syntax :char-range
      (syntax-rules ()
        ((_ rest ...) (error ":char-range used outside a comprehension"))))
    (define-syntax :integers
      (syntax-rules ()
        ((_ rest ...) (error ":integers used outside a comprehension"))))
    (define-syntax :port
      (syntax-rules ()
        ((_ rest ...) (error ":port used outside a comprehension"))))
    (define-syntax :do
      (syntax-rules ()
        ((_ rest ...) (error ":do used outside a comprehension"))))
    (define-syntax :let
      (syntax-rules ()
        ((_ rest ...) (error ":let used outside a comprehension"))))
    (define-syntax :parallel
      (syntax-rules ()
        ((_ rest ...) (error ":parallel used outside a comprehension"))))
    (define-syntax :while
      (syntax-rules ()
        ((_ rest ...) (error ":while used outside a comprehension"))))
    (define-syntax :until
      (syntax-rules ()
        ((_ rest ...) (error ":until used outside a comprehension"))))
    (define-syntax :dispatched
      (syntax-rules ()
        ((_ rest ...) (error ":dispatched used outside a comprehension"))))

    ;; --- Runtime generator procedures (the :dispatched protocol) ---
    ;; A generator procedure g is called as (g empty) and returns the
    ;; next value of its sequence, or `empty' itself once exhausted.
    ;; Each %gen-* must produce the same sequence as its macro
    ;; counterpart in %do-ec.

    (define (%gen-list lsts)
      (let ((cur '()) (rest lsts))
        (lambda (empty)
          (let loop ()
            (cond
              ((pair? cur)
               (let ((x (car cur))) (set! cur (cdr cur)) x))
              ((pair? rest)
               (set! cur (car rest)) (set! rest (cdr rest)) (loop))
              (else empty))))))

    (define (%gen-string strs)
      (let ((cur "") (n 0) (k 0) (rest strs))
        (lambda (empty)
          (let loop ()
            (cond
              ((< k n)
               (let ((c (string-ref cur k))) (set! k (+ k 1)) c))
              ((pair? rest)
               (set! cur (car rest))
               (set! n (string-length cur))
               (set! k 0)
               (set! rest (cdr rest))
               (loop))
              (else empty))))))

    (define (%gen-vector vecs)
      (let ((cur #()) (n 0) (k 0) (rest vecs))
        (lambda (empty)
          (let loop ()
            (cond
              ((< k n)
               (let ((x (vector-ref cur k))) (set! k (+ k 1)) x))
              ((pair? rest)
               (set! cur (car rest))
               (set! n (vector-length cur))
               (set! k 0)
               (set! rest (cdr rest))
               (loop))
              (else empty))))))

    (define (%gen-range from to step)
      (if (zero? step)
          (error "step size must not be zero in :range"))
      (let ((x from))
        (lambda (empty)
          (if (if (positive? step) (< x to) (> x to))
              (let ((v x)) (set! x (+ x step)) v)
              empty))))

    (define (%gen-real-range from to step)
      (if (not (and (real? from) (real? to) (real? step)))
          (error "arguments of :real-range are not real" from to step))
      (if (zero? step)
          (error "step size must not be zero in :real-range"))
      (let* ((a (if (and (exact? from)
                         (not (and (exact? to) (exact? step))))
                    (inexact from)
                    from))
             (istop (/ (- to a) step))
             (i 0))
        (lambda (empty)
          (if (< i istop)
              (let ((v (+ a (* step i)))) (set! i (+ i 1)) v)
              empty))))

    (define (%gen-char-range from to)
      (let ((i (char->integer from)) (imax (char->integer to)))
        (lambda (empty)
          (if (<= i imax)
              (let ((c (integer->char i))) (set! i (+ i 1)) c)
              empty))))

    (define (%gen-port port read-proc)
      (lambda (empty)
        (let ((x (read-proc port)))
          (if (eof-object? x) empty x))))

    (define (%gen-integers)
      (let ((i 0))
        (lambda (empty)
          (let ((v i)) (set! i (+ i 1)) v))))

    ;; Look up a generator procedure via a dispatcher, per :dispatched.
    (define (%dispatch-gproc d args)
      (let ((g (d args)))
        (if (procedure? g)
            g
            (error "unrecognized arguments in dispatching" args (d '())))))

    ;; Turn a producer — a procedure calling its argument once per
    ;; value — into a generator procedure, suspending the producer
    ;; between values with call/cc.  Fallback for generator forms that
    ;; have no %gen-* constructor.
    (define (%make-coroutine-gproc producer)
      (let ((return #f) (resume #f) (done #f))
        (define (yield v)
          (call-with-current-continuation
            (lambda (k)
              (set! resume k)
              (return v))))
        (lambda (empty)
          (if done
              empty
              (call-with-current-continuation
                (lambda (r)
                  (set! return r)
                  (if resume
                      (resume #f)
                      (begin
                        (producer yield)
                        (set! done #t)
                        (return empty)))))))))

    (define (%every? pred xs)
      (or (null? xs)
          (and (pred (car xs)) (%every? pred (cdr xs)))))

    ;; --- The generic dispatcher behind (: var arg ...) ---
    ;; Cases per the spec: all-lists, all-strings, all-vectors; 1-3
    ;; exact integers → :range; 1-3 reals → :real-range; 2 chars →
    ;; :char-range; port [+ reader] → :port.  On zero arguments a
    ;; dispatcher returns an identification instead of a generator
    ;; (dispatch-union's conflict reporting relies on this).
    (define (make-initial-:-dispatch)
      (lambda (args)
        (case (length args)
          ((0) 'SRFI42)
          ((1)
           (let ((a1 (car args)))
             (cond
               ((list? a1) (%gen-list args))
               ((string? a1) (%gen-string args))
               ((vector? a1) (%gen-vector args))
               ((and (integer? a1) (exact? a1)) (%gen-range 0 a1 1))
               ((real? a1) (%gen-real-range 0 a1 1))
               ((input-port? a1) (%gen-port a1 read))
               (else #f))))
          ((2)
           (let ((a1 (car args)) (a2 (cadr args)))
             (cond
               ((and (list? a1) (list? a2)) (%gen-list args))
               ((and (string? a1) (string? a2)) (%gen-string args))
               ((and (vector? a1) (vector? a2)) (%gen-vector args))
               ((and (integer? a1) (exact? a1) (integer? a2) (exact? a2))
                (%gen-range a1 a2 1))
               ((and (real? a1) (real? a2)) (%gen-real-range a1 a2 1))
               ((and (char? a1) (char? a2)) (%gen-char-range a1 a2))
               ((and (input-port? a1) (procedure? a2)) (%gen-port a1 a2))
               (else #f))))
          ((3)
           (let ((a1 (car args)) (a2 (cadr args)) (a3 (caddr args)))
             (cond
               ((and (list? a1) (list? a2) (list? a3)) (%gen-list args))
               ((and (string? a1) (string? a2) (string? a3))
                (%gen-string args))
               ((and (vector? a1) (vector? a2) (vector? a3))
                (%gen-vector args))
               ((and (integer? a1) (exact? a1)
                     (integer? a2) (exact? a2)
                     (integer? a3) (exact? a3))
                (%gen-range a1 a2 a3))
               ((and (real? a1) (real? a2) (real? a3))
                (%gen-real-range a1 a2 a3))
               (else #f))))
          (else
           (cond
             ((%every? list? args) (%gen-list args))
             ((%every? string? args) (%gen-string args))
             ((%every? vector? args) (%gen-vector args))
             (else #f))))))

    (define %the-dispatch (make-initial-:-dispatch))

    (define (:-dispatch-ref) %the-dispatch)

    (define (:-dispatch-set! d)
      (if (not (procedure? d))
          (error ":-dispatch-set!: not a procedure" d))
      (set! %the-dispatch d))

    ;; Combine two dispatchers; error if both claim the same argument
    ;; list.  On '() (the identification convention) the two
    ;; identifications are appended instead.
    (define (dispatch-union d1 d2)
      (lambda (args)
        (let ((g1 (d1 args)) (g2 (d2 args)))
          (if g1
              (if g2
                  (if (null? args)
                      (append (if (list? g1) g1 (list g1))
                              (if (list? g2) g2 (list g2)))
                      (error "dispatching conflict" args (d1 '()) (d2 '())))
                  g1)
              (if g2 g2 #f)))))

    ;; Internal recursive qualifier processor.
    ;; s = mutable stop flag for :while/:until early exit.
    ;; Processes one qualifier per expansion, recurses on the rest.
    ;; The engine caps one syntax-rules form at 32 rules, so the
    ;; qualifier rules are split across two macros: %do-ec holds the
    ;; generators and forwards any other qualifier to %do-ec-more, which
    ;; holds the grouping, command, control, and guard qualifiers.
    (define-syntax %do-ec
      (syntax-rules (:range :real-range :char-range :list :string :vector
                     :integers :port :let :do :parallel : :dispatched let)
        ;; --- generators ---
        ((_ s (:range var n) rest1 rest2 ...)
         (let ((%n n))
           (let %lp ((var 0))
             (when (and (< var %n) (not s))
               (%do-ec s rest1 rest2 ...)
               (%lp (+ var 1))))))
        ((_ s (:range var a b) rest1 rest2 ...)
         (let ((%b b))
           (let %lp ((var a))
             (when (and (< var %b) (not s))
               (%do-ec s rest1 rest2 ...)
               (%lp (+ var 1))))))
        ((_ s (:range var a b c) rest1 rest2 ...)
         (let ((%b b) (%c c))
           (if (zero? %c)
               (error "step size must not be zero in :range"))
           (let %lp ((var a))
             (when (and (if (positive? %c) (< var %b) (> var %b))
                        (not s))
               (%do-ec s rest1 rest2 ...)
               (%lp (+ var %c))))))
        ;; :real-range — i counts 0, 1, ... while i < (to-from)/step and
        ;; var = from + i*step; from turns inexact if to or step is.
        ((_ s (:real-range var b) rest1 rest2 ...)
         (%do-ec s (:real-range var 0 b 1) rest1 rest2 ...))
        ((_ s (:real-range var a b) rest1 rest2 ...)
         (%do-ec s (:real-range var a b 1) rest1 rest2 ...))
        ((_ s (:real-range var a b c) rest1 rest2 ...)
         (let ((%a a) (%b b) (%c c))
           (if (not (and (real? %a) (real? %b) (real? %c)))
               (error "arguments of :real-range are not real" %a %b %c))
           (if (zero? %c)
               (error "step size must not be zero in :real-range"))
           (let* ((%x (if (and (exact? %a)
                               (not (and (exact? %b) (exact? %c))))
                          (inexact %a)
                          %a))
                  (%lim (/ (- %b %x) %c)))
             (let %lp ((%i 0))
               (when (and (< %i %lim) (not s))
                 (let ((var (+ %x (* %c %i))))
                   (%do-ec s rest1 rest2 ...))
                 (%lp (+ %i 1)))))))
        ;; :char-range — both endpoints inclusive.
        ((_ s (:char-range var a b) rest1 rest2 ...)
         (let ((%imax (char->integer b)))
           (let %lp ((%i (char->integer a)))
             (when (and (<= %i %imax) (not s))
               (let ((var (integer->char %i)))
                 (%do-ec s rest1 rest2 ...))
               (%lp (+ %i 1))))))
        ((_ s (:list var lst) rest1 rest2 ...)
         (let %lp ((%xs lst))
           (when (and (pair? %xs) (not s))
             (let ((var (car %xs)))
               (%do-ec s rest1 rest2 ...))
             (%lp (cdr %xs)))))
        ((_ s (:list var lst1 lst2 lst3 ...) rest1 rest2 ...)
         (%do-ec s (:list var (append lst1 lst2 lst3 ...)) rest1 rest2 ...))
        ((_ s (:string var str) rest1 rest2 ...)
         (let* ((%str str) (%n (string-length %str)))
           (let %lp ((%k 0))
             (when (and (< %k %n) (not s))
               (let ((var (string-ref %str %k)))
                 (%do-ec s rest1 rest2 ...))
               (%lp (+ %k 1))))))
        ((_ s (:string var str1 str2 str3 ...) rest1 rest2 ...)
         (%do-ec s (:string var (string-append str1 str2 str3 ...))
                 rest1 rest2 ...))
        ((_ s (:vector var vec) rest1 rest2 ...)
         (let* ((%v vec) (%n (vector-length %v)))
           (let %lp ((%k 0))
             (when (and (< %k %n) (not s))
               (let ((var (vector-ref %v %k)))
                 (%do-ec s rest1 rest2 ...))
               (%lp (+ %k 1))))))
        ((_ s (:vector var vec1 vec2 vec3 ...) rest1 rest2 ...)
         (%do-ec s (:list var (append (vector->list vec1)
                                      (vector->list vec2)
                                      (vector->list vec3) ...))
                 rest1 rest2 ...))
        ((_ s (:integers var) rest1 rest2 ...)
         (let %lp ((var 0))
           (when (not s)
             (%do-ec s rest1 rest2 ...)
             (%lp (+ var 1)))))
        ((_ s (:port var p) rest1 rest2 ...)
         (%do-ec s (:port var p read) rest1 rest2 ...))
        ((_ s (:port var p rd) rest1 rest2 ...)
         (let ((%p p) (%rd rd))
           (let %lp ((var (%rd %p)))
             (when (and (not (eof-object? var)) (not s))
               (%do-ec s rest1 rest2 ...)
               (%lp (%rd %p))))))
        ((_ s (:let var expr) rest1 rest2 ...)
         (let ((var expr))
           (%do-ec s rest1 rest2 ...)))
        ;; --- generic dispatch ---
        ((_ s (: var arg1 arg ...) rest1 rest2 ...)
         (%do-ec s (:dispatched var (:-dispatch-ref) arg1 arg ...)
                 rest1 rest2 ...))
        ((_ s (:dispatched var dispatch arg ...) rest1 rest2 ...)
         (let ((%g (%dispatch-gproc dispatch (list arg ...)))
               (%empty (list #f)))
           (let %lp ((var (%g %empty)))
             (when (and (not (eq? var %empty)) (not s))
               (%do-ec s rest1 rest2 ...)
               (%lp (%g %empty))))))
        ;; --- the fundamental generator :do ---
        ((_ s (:do (lb ...) ne1? (ls ...)) rest1 rest2 ...)
         (%do-ec s (:do (let ()) (lb ...) ne1? (let ()) #t (ls ...))
                 rest1 rest2 ...))
        ((_ s (:do (let (ob ...) oc ...) (lb ...) ne1?
                   (let (ib ...) ic ...) ne2? (ls ...))
            rest1 rest2 ...)
         (let (ob ...)
           oc ...
           (let %lp (lb ...)
             (when (and ne1? (not s))
               (let (ib ...)
                 ic ...
                 (%do-ec s rest1 rest2 ...)
                 (when (and ne2? (not s))
                   (%lp ls ...)))))))
        ;; --- parallel (lockstep) iteration ---
        ((_ s (:parallel gen1 gen2 ...) rest1 rest2 ...)
         (%parallel s () (gen1 gen2 ...) rest1 rest2 ...))
        ;; --- anything else: grouping/command/control/guard qualifiers ---
        ((_ s q rest1 rest2 ...)
         (%do-ec-more s q rest1 rest2 ...))
        ;; --- base case ---
        ((_ s body)
         body)))

    ;; Second half of the qualifier processor (see the %do-ec comment):
    ;; grouping, command, control, and guard qualifiers.  Every recursion
    ;; goes back through %do-ec, the single entry point.
    (define-syntax %do-ec-more
      (syntax-rules (nested begin :while :until %while-xlate %until-xlate
                     if not and or)
        ;; --- qualifier grouping and command qualifiers ---
        ((_ s (nested q ...) rest1 rest2 ...)
         (%do-ec s q ... rest1 rest2 ...))
        ((_ s (begin cmd ...) rest1 rest2 ...)
         (begin cmd ... (%do-ec s rest1 rest2 ...)))
        ;; --- control qualifiers ---
        ;; :while/:until wrapping a generator (spec form): the test stops
        ;; only the generator it wraps, so enclosing loops continue.  The
        ;; wrapped generator runs against its own private stop flag; the
        ;; translator qualifier re-threads the enclosing flag for the
        ;; rest of the chain and mirrors an ambient stop into the private
        ;; flag, so a bare :while/:until deeper in the chain still ends
        ;; this generator's loop.
        ((_ s (:while (g garg ...) test) rest1 rest2 ...)
         (let ((%s2 #f))
           (%do-ec %s2 (g garg ...) (%while-xlate s test) rest1 rest2 ...)))
        ((_ s (:until (g garg ...) test) rest1 rest2 ...)
         (let ((%s2 #f))
           (%do-ec %s2 (g garg ...) (%until-xlate s test) rest1 rest2 ...)))
        ;; Translator qualifiers, generated only by the two rules above:
        ;; s2 is the wrapped generator's flag, outer the enclosing one.
        ((_ s2 (%while-xlate outer test) rest1 rest2 ...)
         (if test
             (begin
               (%do-ec outer rest1 rest2 ...)
               (when outer (set! s2 #t)))
             (set! s2 #t)))
        ((_ s2 (%until-xlate outer test) rest1 rest2 ...)
         (begin
           (%do-ec outer rest1 rest2 ...)
           (when (or test outer) (set! s2 #t))))
        ;; :while/:until as standalone qualifiers (this port's extension:
        ;; stops the whole comprehension — see the header)
        ((_ s (:while test) rest1 rest2 ...)
         (if test
           (%do-ec s rest1 rest2 ...)
           (set! s #t)))
        ((_ s (:until test) rest1 rest2 ...)
         (begin
           (%do-ec s rest1 rest2 ...)
           (when test (set! s #t))))
        ;; --- guards ---
        ((_ s (if test) rest1 rest2 ...)
         (when test (%do-ec s rest1 rest2 ...)))
        ((_ s (not test) rest1 rest2 ...)
         (unless test (%do-ec s rest1 rest2 ...)))
        ((_ s (and test ...) rest1 rest2 ...)
         (when (and test ...) (%do-ec s rest1 rest2 ...)))
        ((_ s (or test ...) rest1 rest2 ...)
         (when (or test ...) (%do-ec s rest1 rest2 ...)))))

    ;; :parallel expansion helper: peel one (gen var arg ...) sub-form
    ;; per recursion step, converting it to a generator procedure (one
    ;; let per step keeps the hygienic %g names distinct), then run all
    ;; of them in lockstep, stopping at the first exhausted generator.
    (define-syntax %parallel
      (syntax-rules ()
        ((_ s (done ...) ((gen var arg ...) more ...) rest1 rest2 ...)
         (let ((%g (:generator-proc (gen arg ...))))
           (%parallel s (done ... (var %g)) (more ...) rest1 rest2 ...)))
        ((_ s ((var g) ...) () rest1 rest2 ...)
         (let ((%e (list #f)))
           (let %lp ((var (g %e)) ...)
             (when (and (not s) (not (eq? var %e)) ...)
               (%do-ec s rest1 rest2 ...)
               (%lp (g %e) ...)))))))

    ;; (:generator-proc (gen arg ...)) — the generator procedure running
    ;; through (list-ec (gen var arg ...) var), per the spec.  Standard
    ;; typed generators compile straight to their %gen-* constructor;
    ;; anything else runs through do-ec inside a call/cc coroutine.
    (define-syntax :generator-proc
      (syntax-rules (: :list :string :vector :range :real-range
                     :char-range :integers :port :dispatched)
        ((_ (:list arg ...)) (%gen-list (list arg ...)))
        ((_ (:string arg ...)) (%gen-string (list arg ...)))
        ((_ (:vector arg ...)) (%gen-vector (list arg ...)))
        ((_ (:range b)) (%gen-range 0 b 1))
        ((_ (:range a b)) (%gen-range a b 1))
        ((_ (:range a b c)) (%gen-range a b c))
        ((_ (:real-range b)) (%gen-real-range 0 b 1))
        ((_ (:real-range a b)) (%gen-real-range a b 1))
        ((_ (:real-range a b c)) (%gen-real-range a b c))
        ((_ (:char-range a b)) (%gen-char-range a b))
        ((_ (:integers)) (%gen-integers))
        ((_ (:port p)) (%gen-port p read))
        ((_ (:port p rd)) (%gen-port p rd))
        ((_ (: arg1 arg ...))
         (%dispatch-gproc (:-dispatch-ref) (list arg1 arg ...)))
        ((_ (:dispatched d arg ...))
         (%dispatch-gproc d (list arg ...)))
        ((_ (g arg ...))
         (%make-coroutine-gproc
           (lambda (%yield)
             (do-ec (g %x arg ...) (%yield %x)))))))

    (define-syntax do-ec
      (syntax-rules ()
        ((_ rest1 rest2 ...)
         (let ((%ec-stop #f))
           (%do-ec %ec-stop rest1 rest2 ...)))))

    (define-syntax list-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (let ((%ec-acc '()))
           (do-ec qualifier ... (set! %ec-acc (cons expr %ec-acc)))
           (reverse %ec-acc)))))

    (define-syntax fold-ec
      (syntax-rules ()
        ((_ seed qualifier ... expr f)
         (let ((%ec-acc seed))
           (do-ec qualifier ... (set! %ec-acc (f expr %ec-acc)))
           %ec-acc))))

    (define-syntax fold3-ec
      (syntax-rules ()
        ((_ x0 qualifier ... expr f1 f2)
         (let ((%ec-first #t) (%ec-acc x0))
           (do-ec qualifier ...
             (if %ec-first
               (begin (set! %ec-acc (f1 expr))
                      (set! %ec-first #f))
               (set! %ec-acc (f2 expr %ec-acc))))
           %ec-acc))))

    (define-syntax string-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (list->string (list-ec qualifier ... expr)))))

    (define-syntax vector-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (list->vector (list-ec qualifier ... expr)))))

    (define-syntax append-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (apply append (list-ec qualifier ... expr)))))

    (define-syntax sum-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (fold-ec 0 qualifier ... expr +))))

    (define-syntax product-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (fold-ec 1 qualifier ... expr *))))

    (define-syntax min-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (apply min (list-ec qualifier ... expr)))))

    (define-syntax max-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (apply max (list-ec qualifier ... expr)))))

    ;; SRFI 42 gives all three accumulators early-exit semantics: first-ec
    ;; "stop[s] the loop after the first value" and any?-ec/every?-ec stop
    ;; "as soon as the result is known" — the spec's own examples use them
    ;; on infinite :integers generators.  Each allocates its own stop flag
    ;; (%s) and sets it from the body; every generator loop in %do-ec
    ;; checks (not s) before each iteration, so setting it unwinds the whole
    ;; comprehension (#2179).
    (define-syntax first-ec
      (syntax-rules ()
        ((_ default qualifier ... expr)
         (let ((%s #f) (%result default))
           (%do-ec %s qualifier ...
                   (begin (set! %result expr) (set! %s #t)))
           %result))))

    (define-syntax last-ec
      (syntax-rules ()
        ((_ default qualifier ... expr)
         (let ((%result (list-ec qualifier ... expr)))
           (if (null? %result) default
               (let %lp ((%ls %result))
                 (if (null? (cdr %ls)) (car %ls) (%lp (cdr %ls)))))))))

    (define-syntax any?-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (let ((%s #f) (%ec-r #f))
           (%do-ec %s qualifier ...
                   (if expr (begin (set! %ec-r #t) (set! %s #t))))
           %ec-r))))

    (define-syntax every?-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (let ((%s #f) (%ec-r #t))
           (%do-ec %s qualifier ...
                   (if (not expr) (begin (set! %ec-r #f) (set! %s #t))))
           %ec-r))))))
