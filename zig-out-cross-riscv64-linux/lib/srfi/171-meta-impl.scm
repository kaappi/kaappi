;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Copyright 2019 Linus Bjornstam
;;
;; You may use this code under either the license in the SRFI document or the
;; license below.
;;
;; Permission to use, copy, modify, and/or distribute this software for any
;; purpose with or without fee is hereby granted, provided that the above
;; copyright notice and this permission notice appear in all source copies.
;; The software is provided "as is", without any express or implied warranties.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; A reduced value stops the transduction.
(define-record-type <reduced>
  (reduced val)
  reduced?
  (val unreduce))

;; helper function which ensures x is reduced.
(define (ensure-reduced x)
  (if (reduced? x)
      x
      (reduced x)))

;; helper function that wraps a reduced value twice since reducing functions
;; (like list-reduce) unwrap them.
(define (preserving-reduced reducer)
  (lambda (a b)
    (let ((return (reducer a b)))
      (if (reduced? return)
          (reduced return)
          return))))

;; This is where the magic tofu is cooked
(define (list-reduce f identity lst)
  (if (null? lst)
      identity
      (let ((v (f identity (car lst))))
        (if (reduced? v)
            (unreduce v)
            (list-reduce f v (cdr lst))))))

(define (vector-reduce f identity vec)
  (let ((len (vector-length vec)))
    (let loop ((i 0) (acc identity))
      (if (= i len)
          acc
          (let ((acc (f acc (vector-ref vec i))))
            (if (reduced? acc)
                (unreduce acc)
                (loop (+ i 1) acc)))))))

(define (string-reduce f identity str)
  (let ((len (string-length str)))
    (let loop ((i 0) (acc identity))
      (if (= i len)
          acc
          (let ((acc (f acc (string-ref str i))))
            (if (reduced? acc)
                (unreduce acc)
                (loop (+ i 1) acc)))))))

(define (bytevector-u8-reduce f identity vec)
  (let ((len (bytevector-length vec)))
    (let loop ((i 0) (acc identity))
      (if (= i len)
          acc
          (let ((acc (f acc (bytevector-u8-ref vec i))))
            (if (reduced? acc)
                (unreduce acc)
                (loop (+ i 1) acc)))))))

(define (port-reduce f identity reader port)
  (let loop ((val (reader port)) (acc identity))
    (if (eof-object? val)
        acc
        (let ((acc (f acc val)))
          (if (reduced? acc)
              (unreduce acc)
              (loop (reader port) acc))))))

(define (generator-reduce f identity gen)
  (let loop ((val (gen)) (acc identity))
    (if (eof-object? val)
        acc
        (let ((acc (f acc val)))
          (if (reduced? acc)
              (unreduce acc)
              (loop (gen) acc))))))
