;;; SRFI 43 — Vector Library
;;; SRFI-43 iteration procedures pass the index as the first callback
;;; argument; SRFI-133 does not.  Procedures with identical semantics
;;; are re-exported directly from SRFI-133.
(define-library (srfi 43)
  (import (scheme base)
          (except (srfi 133)
                  vector-map! vector-count
                  vector-fold vector-fold-right))
  (export make-vector vector vector? vector-ref vector-set! vector-length
          vector-fold vector-fold-right
          vector-map vector-map!
          vector-for-each
          vector-count
          vector-index vector-index-right
          vector-skip vector-skip-right
          vector-any vector-every
          vector-binary-search
          vector-copy vector-copy!
          vector-reverse-copy vector-reverse-copy!
          vector-fill!
          vector-swap!
          vector-reverse!
          vector-append vector-concatenate
          vector-empty?
          vector-unfold vector-unfold-right
          vector=
          vector->list list->vector
          reverse-vector->list reverse-list->vector)
  (begin
    ;; SRFI-43 vector-fold: (kons i state elt1 elt2 ...) — left to right
    (define (vector-fold kons knil . vecs)
      (let ((len (apply min (map vector-length vecs))))
        (let loop ((i 0) (state knil))
          (if (= i len) state
              (loop (+ i 1)
                    (apply kons i state
                           (map (lambda (v) (vector-ref v i)) vecs)))))))

    ;; SRFI-43 vector-fold-right: (kons i state elt1 elt2 ...) — right to left
    (define (vector-fold-right kons knil . vecs)
      (let ((len (apply min (map vector-length vecs))))
        (let loop ((i (- len 1)) (state knil))
          (if (< i 0) state
              (loop (- i 1)
                    (apply kons i state
                           (map (lambda (v) (vector-ref v i)) vecs)))))))

    ;; SRFI-43 vector-map: (f i elt1 elt2 ...) — returns new vector
    (define (vector-map f . vecs)
      (let* ((len (apply min (map vector-length vecs)))
             (result (make-vector len)))
        (let loop ((i 0))
          (when (< i len)
            (vector-set! result i
                         (apply f i (map (lambda (v) (vector-ref v i)) vecs)))
            (loop (+ i 1))))
        result))

    ;; SRFI-43 vector-map!: (f i elt1 elt2 ...) — mutates first vector
    (define (vector-map! f vec . vecs)
      (let ((len (apply min (vector-length vec)
                        (map vector-length vecs))))
        (let loop ((i 0))
          (when (< i len)
            (vector-set! vec i
                         (apply f i
                                (cons (vector-ref vec i)
                                      (map (lambda (v) (vector-ref v i)) vecs))))
            (loop (+ i 1))))))

    ;; SRFI-43 vector-for-each: (f i elt1 elt2 ...) — left to right
    (define (vector-for-each f . vecs)
      (let ((len (apply min (map vector-length vecs))))
        (let loop ((i 0))
          (when (< i len)
            (apply f i (map (lambda (v) (vector-ref v i)) vecs))
            (loop (+ i 1))))))

    ;; SRFI-43 vector-count: (pred? i elt1 elt2 ...)
    (define (vector-count pred? . vecs)
      (let ((len (apply min (map vector-length vecs))))
        (let loop ((i 0) (count 0))
          (if (= i len) count
              (loop (+ i 1)
                    (if (apply pred? i
                               (map (lambda (v) (vector-ref v i)) vecs))
                        (+ count 1)
                        count))))))))
