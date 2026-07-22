;;; SRFI 161 — Unifiable Boxes
;;;
;;; Union-find with path compression and union by rank, per the SRFI's own
;;; suggested implementation strategy. Each ubox is a mutable-pair-style
;;; record: a "parent" slot (either #f for a root, or another ubox) and,
;;; when a root, a "rank" and the shared "value". ubox-ref/-set!/-unify!
;;; walk to the root (compressing the path as they go) to find the live
;;; value slot.

(define-library (srfi 161)
  (import (scheme base))
  (export ubox ubox? ubox-ref ubox-set! ubox=?
          ubox-unify! ubox-union! ubox-link!)
  (begin

    (define-record-type <ubox>
      (%make-ubox parent rank value)
      ubox?
      (parent %ubox-parent %ubox-set-parent!)
      (rank %ubox-rank %ubox-set-rank!)
      (value %ubox-value %ubox-set-value!))

    (define (ubox value)
      (%make-ubox #f 0 value))

    ;; Finds the root of b's equivalence class, compressing the path so
    ;; every box visited now points directly at the root.
    (define (%find-root b)
      (let ((p (%ubox-parent b)))
        (if (not p)
            b
            (let ((root (%find-root p)))
              (%ubox-set-parent! b root)
              root))))

    (define (ubox-ref b)
      (%ubox-value (%find-root b)))

    (define (ubox-set! b value)
      (%ubox-set-value! (%find-root b) value))

    (define (ubox=? b1 b2)
      (eq? (%find-root b1) (%find-root b2)))

    ;; Shared union-by-rank merge: links the lower-rank root under the
    ;; higher-rank one (ties broken toward r2, then bumped), and installs
    ;; whatever value the caller computes for the surviving root.
    (define (%union-with-value! b1 b2 compute-value)
      (let* ((r1 (%find-root b1))
             (r2 (%find-root b2)))
        (if (eq? r1 r2)
            (%ubox-set-value! r1 (compute-value))
            (let ((rank1 (%ubox-rank r1))
                  (rank2 (%ubox-rank r2))
                  (new-value (compute-value)))
              (cond
                ((< rank1 rank2)
                 (%ubox-set-parent! r1 r2)
                 (%ubox-set-value! r2 new-value))
                ((> rank1 rank2)
                 (%ubox-set-parent! r2 r1)
                 (%ubox-set-value! r1 new-value))
                (else
                 (%ubox-set-parent! r2 r1)
                 (%ubox-set-rank! r1 (+ rank1 1))
                 (%ubox-set-value! r1 new-value)))))))

    (define (ubox-unify! proc b1 b2)
      (let ((v1 (ubox-ref b1)) (v2 (ubox-ref b2)))
        (%union-with-value! b1 b2 (lambda () (proc v1 v2)))))

    (define (ubox-union! b1 b2)
      (let ((v1 (ubox-ref b1)))
        (%union-with-value! b1 b2 (lambda () v1))))

    (define (ubox-link! b1 b2)
      (let ((v2 (ubox-ref b2)))
        (%union-with-value! b1 b2 (lambda () v2))))))
