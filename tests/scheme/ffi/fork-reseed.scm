;; Regression test: a fork(2)ed child must not inherit the parent's default
;; random source PRNG state. The default source is created eagerly at VM
;; startup, so before this fix EVERY forked child (e.g. kaappi-http's
;; http-listen-prefork workers) continued the parent's exact stream — all
;; workers drew identical values, which meant identical kaappi-web session
;; ids across workers. The pthread_atfork child handler marks the source
;; stale and the next draw reseeds it in place from OS entropy.
(import (scheme base) (scheme write) (scheme file) (scheme process-context))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(cond-expand
  (posix

   (define libc (ffi-open #f))
   (define c-fork (ffi-fn libc "fork" '() 'int))
   (define c-wait (ffi-fn libc "wait" '(pointer) 'int))

   (define (draw-n n)
     (let loop ((i 0) (acc '()))
       (if (= i n)
           (reverse acc)
           (loop (+ i 1) (cons (random-integer 1000000000) acc)))))

   ;; Advance the parent's default source so fork copies a mid-stream
   ;; state, then agree on a scratch path before forking.
   (define tmpfile
     (string-append "/tmp/kaappi-fork-reseed-"
                    (number->string (random-integer 1000000))
                    ".tmp"))
   (define warmup (draw-n 3))

   (flush-output-port (current-output-port))
   (let ((pid (c-fork)))
     (cond
       ((= pid 0)
        ;; Child: draw and report back through the scratch file. Exit on
        ;; every path so the child can never fall through into the
        ;; parent's half of the test.
        (guard (e (#t (exit 70)))
          (call-with-output-file tmpfile
            (lambda (p) (write (draw-n 8) p))))
        (exit 0))
       ((> pid 0)
        (c-wait 0)
        (let ((parent-draws (draw-n 8))
              (child-draws (and (file-exists? tmpfile)
                                (call-with-input-file tmpfile read))))
          (check "child wrote 8 draws"
                 (and (list? child-draws) (length child-draws)) 8)
          ;; Before the fix these were equal element-for-element: the child
          ;; continued the parent's PRNG stream. After it, the child's
          ;; first draw reseeds from fresh OS entropy.
          (check "child draws differ from parent's post-fork draws"
                 (equal? child-draws parent-draws) #f)
          (when (file-exists? tmpfile) (delete-file tmpfile))))
       (else
        (check "fork succeeded" (> pid 0) #t)))))

  (else
   (display "SKIP: fork-reseed needs POSIX fork") (newline)))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "fork-reseed tests failed" fail))
