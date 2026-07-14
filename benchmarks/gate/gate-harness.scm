;; KEP-0002 Phase 7 gate-campaign harness (kaappi#1472).
;;
;; Runs ONE benchmark cell -- (workload, size, workers, lever) -- for a given
;; number of warmup + measured iterations, printing one machine-readable line
;; per measured iteration for the Kalibera-Jones driver (run-gate.py) to
;; aggregate. The frozen protocol is keps research/benchmarks/README.md; this
;; file realizes its §1 workloads and §3 metrics.
;;
;; Usage:
;;   kaappi gate-harness.scm <workload> <size-bytes> <workers> <lever> <warmup> <iters>
;;
;;   workload : ip-band ip-map ip-matmul fo-digest fo-tree fo-slice c-empty
;;              | s:ip-band s:ip-map s:ip-matmul s:fo-digest s:fo-tree s:fo-slice
;;              (an "s:" prefix runs the single-thread, no-pool serial baseline S)
;;   lever    : none | c | cd   (envelope elision lever; §2)
;;
;; Output, one per measured iteration:
;;   ITER <workload> <size> <workers> <lever> <iter> \
;;        <e_ns> <submit_ns> <result_ns> <reassembly_ns> <peak_env_bytes> <checksum>
;;
;; DESIGN NOTES
;;
;;  * The §1 workloads are "in-place-shaped" (IP-*) and "read-only fan-out"
;;    (FO-*). Each is realized with the chunked worker-pool idiom -- make-pool w;
;;    submit exactly w disjoint tasks; task-wait each; reassemble -- NOT
;;    parallel-map over a per-element list. This is what §1 actually describes
;;    (disjoint bands / chunks / blocks) and is also lib/kaappi/parallel.sld's
;;    documented recommendation for large inputs, sidestepping the kaappi#1489
;;    many-submission wakeup hazard (w is small).
;;
;;  * Every worker task thunk is FULLY SELF-CONTAINED: it captures only fixnums,
;;    flonums, and payload objects, and calls only built-in primitives -- never a
;;    top-level procedure defined in this file. A closure that crosses a worker
;;    boundary and then calls a separately-defined procedure can hang
;;    (kaappi#1520); the serial baselines, which never cross a thread, are free to
;;    call the shared top-level kernels.
;;
;;  * E (§3) is wall time from the first pool-submit to the last reassembly copy;
;;    pool creation/teardown and payload construction are excluded (they are
;;    per-cell setup, amortized across iterations by reusing one pool + payload).
;;
;;  * submit/result copy time comes from the real shared_channel path via the
;;    threadlocal counters (%chan-instr-*); reassembly time is bracketed
;;    explicitly around each parent-side output copy. All three are ns.

(import (scheme base)
        (scheme write)
        (scheme process-context)
        (scheme time)
        (kaappi fibers)
        (kaappi parallel))

;; -------------------------------------------------------------------------
;; small helpers
;; -------------------------------------------------------------------------

;; Trailing n elements of a list (robust to whether (command-line) prepends the
;; interpreter and/or script name).
(define (last-n lst n)
  (let loop ((l lst) (len (length lst)))
    (if (> len n) (loop (cdr l) (- len 1)) l)))

;; Disjoint covering chunk for worker wi of `total` items across `workers`:
;; returns (cons start len). The first (remainder) workers get one extra item.
(define (chunk total workers wi)
  (let* ((base (quotient total workers))
         (rem (remainder total workers))
         (start (+ (* wi base) (if (< wi rem) wi rem)))
         (len (+ base (if (< wi rem) 1 0))))
    (cons start len)))

;; Integer square root (for the MxM matmul sizing).
(define (isqrt n)
  (if (< n 2)
      n
      (let loop ((x n) (y (quotient (+ n 1) 2)))
        (if (< y x)
            (loop y (quotient (+ y (quotient n y)) 2))
            x))))

;; -------------------------------------------------------------------------
;; The measured parallel section (§3 E boundary). `make-task` maps a worker
;; index to a self-contained 0-arg task thunk; `reassemble!` folds/copies one
;; worker's result into the shared output on the parent, timed as reassembly.
;; Returns (list e_ns submit_ns result_ns reassembly_ns peak_env_bytes).
;; -------------------------------------------------------------------------
(define (timed-parallel pool workers make-task reassemble!)
  (%chan-instr-reset!)
  (let* ((t0 (current-jiffy))
         (replies (map (lambda (wi) (pool-submit pool (make-task wi)))
                       (iota workers))))
    (for-each (lambda (wi reply)
                (let ((res (task-wait reply)))
                  (%chan-instr-reassembly-begin!)
                  (reassemble! wi res)
                  (%chan-instr-reassembly-end!)))
              (iota workers) replies)
    (let ((e-ns (* (- (current-jiffy) t0) 1000)))
      (list e-ns
            (%chan-instr-submit-ns)
            (%chan-instr-result-ns)
            (%chan-instr-reassembly-ns)
            (%chan-instr-envelope-peak-bytes)))))

;; Serial baseline S (§1 C-SERIAL): same kernel, single thread, no pool, no
;; channels. `body` runs the whole computation and returns a checksum. Returns
;; (list e_ns 0 0 0 0) so the two paths share a print format.
(define (timed-serial body)
  (let ((t0 (current-jiffy)))
    (let ((_ (body)))
      (let ((e-ns (* (- (current-jiffy) t0) 1000)))
        (list e-ns 0 0 0 0)))))

;; NOTE ON SERIAL BASELINES (S): the serial body runs exactly the kernel's
;; compute and returns the output object -- no extra verification pass inside
;; the timed region, so S is comparable to the parallel section's E. (An earlier
;; draft checksummed the whole output in the serial body only, which inflated S
;; and produced spurious superlinear speedups.) The workloads write to a
;; captured output vector/bytevector, so the interpreter cannot elide the work.

;; =========================================================================
;; IP-BAND -- RGBA image bytevector; each worker renders a disjoint row band
;; (per-pixel arithmetic), returns its band; parent bytevector-copy!s into out.
;; =========================================================================
(define ip-band-width 256)

(define (ip-band-height size) (quotient size (* 4 ip-band-width)))

(define (make-ip-band size workers)
  (let* ((width ip-band-width)
         (height (ip-band-height size))
         (out (make-bytevector (* 4 width height) 0)))
    (lambda (pool)
      (timed-parallel
       pool workers
       (lambda (wi)
         (let* ((cb (chunk height workers wi))
                (row0 (car cb)) (rows (cdr cb)) (w width))
           ;; self-contained: captures w, row0, rows (fixnums); primitives only
           (lambda ()
             (let ((band (make-bytevector (* 4 w rows) 0)))
               (let rloop ((r 0))
                 (when (< r rows)
                   (let ((y (+ row0 r)))
                     (let xloop ((x 0))
                       (when (< x w)
                         (let ((base (* 4 (+ (* r w) x))))
                           (bytevector-u8-set! band base (modulo (+ x y) 256))
                           (bytevector-u8-set! band (+ base 1) (modulo (* x 2) 256))
                           (bytevector-u8-set! band (+ base 2) (modulo (* y 3) 256))
                           (bytevector-u8-set! band (+ base 3) 255))
                         (xloop (+ x 1)))))
                   (rloop (+ r 1))))
               band))))
       (lambda (wi band)
         (let* ((cb (chunk height workers wi))
                (row0 (car cb)))
           (bytevector-copy! out (* 4 width row0) band)))))))

;; serial baseline: render the whole image in one thread
(define (make-ip-band-serial size workers)
  (let* ((width ip-band-width)
         (height (ip-band-height size))
         (out (make-bytevector (* 4 width height) 0)))
    (lambda (_pool)
      (timed-serial
       (lambda ()
         (let rloop ((y 0))
           (when (< y height)
             (let xloop ((x 0))
               (when (< x width)
                 (let ((base (* 4 (+ (* y width) x))))
                   (bytevector-u8-set! out base (modulo (+ x y) 256))
                   (bytevector-u8-set! out (+ base 1) (modulo (* x 2) 256))
                   (bytevector-u8-set! out (+ base 2) (modulo (* y 3) 256))
                   (bytevector-u8-set! out (+ base 3) 255))
                 (xloop (+ x 1))))
             (rloop (+ y 1))))
         out)))))

;; =========================================================================
;; IP-MAP -- vector of flonums; out[i] = a*x[i]+b over a disjoint chunk.
;; Task carries the chunk (copied in); returns transformed chunk; parent
;; vector-copy!s into out.
;; =========================================================================
(define (ip-map-n size) (quotient size 8))

(define (make-ip-map size workers)
  (let* ((n (ip-map-n size))
         (xs (make-vector n 0.0))
         (out (make-vector n 0.0))
         (chunks (make-vector workers #f)))
    (do ((i 0 (+ i 1))) ((= i n)) (vector-set! xs i (exact->inexact i)))
    ;; Pre-slice the per-worker chunks ONCE, as setup outside the timed region:
    ;; the task then just carries its chunk, so the only submit-time copy is the
    ;; envelope deepCopy (T_submit_copy), matching §1's "carries the chunk
    ;; (copied in)" -- slicing xs inside E would add parent copy work that no
    ;; counter attributes, diluting `share`.
    (do ((wi 0 (+ wi 1))) ((= wi workers))
      (let* ((cb (chunk n workers wi)) (start (car cb)) (len (cdr cb))
             (cv (make-vector len 0.0)))
        (do ((i 0 (+ i 1))) ((= i len)) (vector-set! cv i (vector-ref xs (+ start i))))
        (vector-set! chunks wi cv)))
    (lambda (pool)
      (timed-parallel
       pool workers
       (lambda (wi)
         (let* ((cv (vector-ref chunks wi))
                (len (vector-length cv)))
           (lambda ()
             (let ((r (make-vector len 0.0)))
               (do ((i 0 (+ i 1))) ((= i len))
                 (vector-set! r i (+ (* 2.5 (vector-ref cv i)) 1.0)))
               r))))
       (lambda (wi r)
         (let* ((cb (chunk n workers wi))
                (start (car cb)) (len (cdr cb)))
           (vector-copy! out start r 0 len)))))))

(define (make-ip-map-serial size workers)
  (let* ((n (ip-map-n size))
         (xs (make-vector n 0.0))
         (out (make-vector n 0.0)))
    (do ((i 0 (+ i 1))) ((= i n)) (vector-set! xs i (exact->inexact i)))
    (lambda (_pool)
      (timed-serial
       (lambda ()
         (do ((i 0 (+ i 1))) ((= i n))
           (vector-set! out i (+ (* 2.5 (vector-ref xs i)) 1.0)))
         out)))))

;; =========================================================================
;; IP-MATMUL -- two MxM f64 matrices (row-major flonum vectors). Each worker
;; computes a disjoint row block of C, reading all of A and B. Tasks carry A
;; and B whole (fan-in copy) plus the block spec; parent assembles C.
;; =========================================================================
(define (matmul-dim size) (isqrt (quotient size 16)))  ; 2 * M*M * 8 bytes = size

(define (make-ip-matmul size workers)
  (let* ((m (matmul-dim size))
         (a (make-vector (* m m) 0.0))
         (b (make-vector (* m m) 0.0))
         (c (make-vector (* m m) 0.0)))
    (do ((i 0 (+ i 1))) ((= i (* m m)))
      (vector-set! a i (exact->inexact (modulo i 7)))
      (vector-set! b i (exact->inexact (modulo i 5))))
    (lambda (pool)
      (timed-parallel
       pool workers
       (lambda (wi)
         (let* ((cb (chunk m workers wi))
                (r0 (car cb)) (rows (cdr cb)))
           ;; captures a, b (whole, fan-in copy), m, r0, rows
           (lambda ()
             (let ((block (make-vector (* rows m) 0.0)))
               (do ((ri 0 (+ ri 1))) ((= ri rows))
                 (let ((arow (* (+ r0 ri) m)))
                   (do ((j 0 (+ j 1))) ((= j m))
                     (let loop ((k 0) (acc 0.0))
                       (if (< k m)
                           (loop (+ k 1)
                                 (+ acc (* (vector-ref a (+ arow k))
                                           (vector-ref b (+ (* k m) j)))))
                           (vector-set! block (+ (* ri m) j) acc))))))
               block))))
       (lambda (wi block)
         (let* ((cb (chunk m workers wi))
                (r0 (car cb)) (rows (cdr cb)))
           (vector-copy! c (* r0 m) block 0 (* rows m))))))))

(define (make-ip-matmul-serial size workers)
  (let* ((m (matmul-dim size))
         (a (make-vector (* m m) 0.0))
         (b (make-vector (* m m) 0.0))
         (c (make-vector (* m m) 0.0)))
    (do ((i 0 (+ i 1))) ((= i (* m m)))
      (vector-set! a i (exact->inexact (modulo i 7)))
      (vector-set! b i (exact->inexact (modulo i 5))))
    (lambda (_pool)
      (timed-serial
       (lambda ()
         (do ((i 0 (+ i 1))) ((= i m))
           (let ((arow (* i m)))
             (do ((j 0 (+ j 1))) ((= j m))
               (let loop ((k 0) (acc 0.0))
                 (if (< k m)
                     (loop (+ k 1)
                           (+ acc (* (vector-ref a (+ arow k))
                                     (vector-ref b (+ (* k m) j)))))
                     (vector-set! c (+ arow j) acc))))))
         c)))))

;; =========================================================================
;; FO-DIGEST -- each worker computes an 8-byte checksum of the WHOLE payload
;; (payload copied to every worker); result is a fixnum pair. Parent folds.
;; =========================================================================
(define (make-fo-digest size workers)
  (let ((payload (make-bytevector size 0))
        (acc (make-vector 1 0)))
    (do ((i 0 (+ i 1))) ((= i size)) (bytevector-u8-set! payload i (modulo i 251)))
    (lambda (pool)
      (vector-set! acc 0 0)
      (timed-parallel
       pool workers
       (lambda (wi)
         ;; captures the WHOLE payload (fan-out copy) -- the point of FO-*
         (lambda ()
           (let ((n (bytevector-length payload)))
             (let loop ((i 0) (lo 0) (hi 0))
               (if (< i n)
                   (let ((nlo (modulo (+ (* lo 31) (bytevector-u8-ref payload i)) 65521)))
                     (loop (+ i 1) nlo (modulo (+ hi nlo) 65521)))
                   (cons lo hi))))))
       (lambda (wi r)
         (vector-set! acc 0 (+ (vector-ref acc 0) (car r) (cdr r))))))))

(define (make-fo-digest-serial size workers)
  (let ((payload (make-bytevector size 0)))
    (do ((i 0 (+ i 1))) ((= i size)) (bytevector-u8-set! payload i (modulo i 251)))
    (lambda (_pool)
      (timed-serial
       (lambda ()
         (let ((n (bytevector-length payload)))
           (let loop ((i 0) (lo 0) (hi 0))
             (if (< i n)
                 (let ((nlo (modulo (+ (* lo 31) (bytevector-u8-ref payload i)) 65521)))
                   (loop (+ i 1) nlo (modulo (+ hi nlo) 65521)))
                 (+ lo hi)))))))))

;; =========================================================================
;; FO-SLICE -- vector of flonums; each worker sums only its index range but
;; receives the WHOLE vector (the over-copying idiom). Result is a flonum.
;; =========================================================================
(define (make-fo-slice size workers)
  (let* ((n (ip-map-n size))
         (xs (make-vector n 0.0))
         (acc (make-vector 1 0.0)))
    (do ((i 0 (+ i 1))) ((= i n)) (vector-set! xs i (exact->inexact (modulo i 97))))
    (lambda (pool)
      (vector-set! acc 0 0.0)
      (timed-parallel
       pool workers
       (lambda (wi)
         (let* ((cb (chunk n workers wi))
                (start (car cb)) (len (cdr cb)))
           ;; captures the WHOLE xs (over-copy) + its own [start,len)
           (lambda ()
             (let loop ((i 0) (s 0.0))
               (if (< i len)
                   (loop (+ i 1) (+ s (vector-ref xs (+ start i))))
                   s)))))
       (lambda (wi r)
         (vector-set! acc 0 (+ (vector-ref acc 0) r)))))))

(define (make-fo-slice-serial size workers)
  (let* ((n (ip-map-n size))
         (xs (make-vector n 0.0)))
    (do ((i 0 (+ i 1))) ((= i n)) (vector-set! xs i (exact->inexact (modulo i 97))))
    (lambda (_pool)
      (timed-serial
       (lambda ()
         (let loop ((i 0) (s 0.0))
           (if (< i n) (loop (+ i 1) (+ s (vector-ref xs i))) s)))))))

;; =========================================================================
;; FO-TREE -- balanced binary tree of nodes (tag a symbol, symbol-heavy). Each
;; worker counts nodes matching a tag over the WHOLE tree (copied to every
;; worker). Result is a fixnum. Doubles as the §1 symbol-table probe.
;;
;; PROTOCOL DEVIATION (flagged pre-freeze): §1 specifies nodes as *records*
;; via `define-record-type`. Records cannot cross a Kaappi channel and still be
;; used by an accessor: deepCopy mints a fresh RecordType per envelope, so a
;; copied instance no longer matches the top-level record type the accessor
;; closes over (record-type identity is not preserved across the copy, unlike
;; symbols, which are interned). A node is therefore a 4-slot vector
;; #(left right tag count) here -- same shape and the same symbol-heaviness (the
;; §1 point), but with a representation that survives the fan-out copy. The
;; underlying limitation must be resolved (or this deviation adopted) before the
;; frozen run; see benchmarks/gate/README.md.
;; =========================================================================
(define fo-tree-tags
  (vector 'alpha 'beta 'gamma 'delta 'epsilon 'zeta 'eta 'theta
          'iota 'kappa 'lambda 'mu 'nu 'xi 'omicron 'pi))

;; ~40 bytes/node (vector header + 4 slots); build n = size/40 nodes.
(define (fo-tree-count size) (max 1 (quotient size 40)))

;; balanced tree of exactly `n` nodes, tags cycled from the pool
(define (build-tree n)
  (let ((counter (make-vector 1 0)))
    (define (build k)
      (if (<= k 0)
          #f
          (let* ((left-k (quotient (- k 1) 2))
                 (right-k (- k 1 left-k))
                 (l (build left-k))
                 (tagi (modulo (vector-ref counter 0) (vector-length fo-tree-tags))))
            (vector-set! counter 0 (+ (vector-ref counter 0) 1))
            (vector l (build right-k)
                    (vector-ref fo-tree-tags tagi)
                    (vector-ref counter 0)))))
    (build n)))

(define (make-fo-tree size workers)
  (let ((tree (build-tree (fo-tree-count size)))
        (acc (make-vector 1 0)))
    (lambda (pool)
      (vector-set! acc 0 0)
      (timed-parallel
       pool workers
       (lambda (wi)
         ;; captures the WHOLE tree (fan-out copy of a symbol-heavy graph);
         ;; counts nodes whose tag is 'gamma. Traversal uses an explicit stack
         ;; list so the thunk calls no top-level helper (kaappi#1520).
         (lambda ()
           (let loop ((stack (list tree)) (cnt 0))
             (if (null? stack)
                 cnt
                 (let ((nd (car stack)))
                   (if nd
                       (loop (cons (vector-ref nd 0)
                                   (cons (vector-ref nd 1) (cdr stack)))
                             (if (eq? (vector-ref nd 2) 'gamma) (+ cnt 1) cnt))
                       (loop (cdr stack) cnt)))))))
       (lambda (wi r)
         (vector-set! acc 0 (+ (vector-ref acc 0) r)))))))

(define (make-fo-tree-serial size workers)
  (let ((tree (build-tree (fo-tree-count size))))
    (lambda (_pool)
      (timed-serial
       (lambda ()
         (let loop ((stack (list tree)) (cnt 0))
           (if (null? stack)
               cnt
               (let ((nd (car stack)))
                 (if nd
                     (loop (cons (vector-ref nd 0) (cons (vector-ref nd 1) (cdr stack)))
                           (if (eq? (vector-ref nd 2) 'gamma) (+ cnt 1) cnt))
                     (loop (cdr stack) cnt))))))))))

;; =========================================================================
;; C-EMPTY -- control-plane floor: submit -> worker no-op -> reply.
;; =========================================================================
(define (make-c-empty size workers)
  (let ((acc (make-vector 1 0)))
    (lambda (pool)
      (vector-set! acc 0 0)
      (timed-parallel
       pool workers
       (lambda (wi) (lambda () 0))
       (lambda (wi r) (vector-set! acc 0 (+ (vector-ref acc 0) r)))))))

;; -------------------------------------------------------------------------
;; dispatch
;; -------------------------------------------------------------------------
(define (workload->maker name)
  (cond
   ((string=? name "ip-band")     make-ip-band)
   ((string=? name "ip-map")      make-ip-map)
   ((string=? name "ip-matmul")   make-ip-matmul)
   ((string=? name "fo-digest")   make-fo-digest)
   ((string=? name "fo-slice")    make-fo-slice)
   ((string=? name "fo-tree")     make-fo-tree)
   ((string=? name "c-empty")     make-c-empty)
   ((string=? name "s:ip-band")   make-ip-band-serial)
   ((string=? name "s:ip-map")    make-ip-map-serial)
   ((string=? name "s:ip-matmul") make-ip-matmul-serial)
   ((string=? name "s:fo-digest") make-fo-digest-serial)
   ((string=? name "s:fo-slice")  make-fo-slice-serial)
   ((string=? name "s:fo-tree")   make-fo-tree-serial)
   (else (error "unknown workload" name))))

(define (serial-workload? name)
  (and (> (string-length name) 2) (string=? (substring name 0 2) "s:")))

;; -------------------------------------------------------------------------
;; main
;; -------------------------------------------------------------------------
(define (run)
  (let* ((argv (last-n (command-line) 6))
         (workload (list-ref argv 0))
         (size (string->number (list-ref argv 1)))
         (workers (string->number (list-ref argv 2)))
         (lever (list-ref argv 3))
         (warmup (string->number (list-ref argv 4)))
         (iters (string->number (list-ref argv 5)))
         (serial? (serial-workload? workload)))
    (%elision-lever-set! (string->symbol lever))
    (let* ((maker (workload->maker workload))
           (cell (maker size workers))
           ;; serial baselines take no pool; parallel cells reuse one pool
           (pool (if serial? #f (make-pool workers))))
      (do ((i 0 (+ i 1))) ((= i warmup)) (cell pool))
      (do ((i 0 (+ i 1))) ((= i iters))
        (let ((r (cell pool)))
          (display "ITER ") (display workload)
          (display " ") (display size)
          (display " ") (display workers)
          (display " ") (display lever)
          (display " ") (display i)
          (for-each (lambda (x) (display " ") (display x)) r)
          (newline)))
      (unless serial? (pool-shutdown! pool)))))

(run)
