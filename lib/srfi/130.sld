;;; SRFI 130 — Cursor-based String Library
;;; Cursors are integer indices (codepoint positions)
(define-library (srfi 130)
  (import (scheme base) (scheme char))
  (export string-cursor? string-cursor-start string-cursor-end
          string-cursor-next string-cursor-prev
          string-cursor-forward string-cursor-back
          string-cursor=? string-cursor<? string-cursor>?
          string-cursor<=? string-cursor>=?
          string-cursor-ref
          string-cursor->index string-index->cursor
          substring/cursors
          string-contains string-contains-right
          string-filter string-remove
          string-count
          string-take string-drop
          string-take-right string-drop-right
          string-prefix? string-suffix?)
  (begin

    (define (string-cursor? x) (integer? x))
    (define (string-cursor-start s) 0)
    (define (string-cursor-end s) (string-length s))
    (define (string-cursor-next s cursor) (+ cursor 1))
    (define (string-cursor-prev s cursor) (- cursor 1))
    (define (string-cursor-forward s cursor n) (+ cursor n))
    (define (string-cursor-back s cursor n) (- cursor n))
    (define (string-cursor=? c1 c2) (= c1 c2))
    (define (string-cursor<? c1 c2) (< c1 c2))
    (define (string-cursor>? c1 c2) (> c1 c2))
    (define (string-cursor<=? c1 c2) (<= c1 c2))
    (define (string-cursor>=? c1 c2) (>= c1 c2))
    (define (string-cursor-ref s cursor) (string-ref s cursor))
    (define (string-cursor->index s cursor) cursor)
    (define (string-index->cursor s index) index)

    (define (substring/cursors s start end)
      (substring s start end))

    (define (string-contains s1 s2)
      (let ((len1 (string-length s1))
            (len2 (string-length s2)))
        (let loop ((i 0))
          (cond
            ((> (+ i len2) len1) #f)
            ((string=? (substring s1 i (+ i len2)) s2) i)
            (else (loop (+ i 1)))))))

    (define (string-contains-right s1 s2)
      (let ((len1 (string-length s1))
            (len2 (string-length s2)))
        (let loop ((i (- len1 len2)))
          (cond
            ((< i 0) #f)
            ((string=? (substring s1 i (+ i len2)) s2) i)
            (else (loop (- i 1)))))))

    (define (string-count s pred)
      (let loop ((i 0) (n 0))
        (if (= i (string-length s)) n
            (loop (+ i 1)
                  (if (pred (string-ref s i)) (+ n 1) n)))))

    (define (string-filter pred s)
      (let ((port (open-output-string)))
        (let loop ((i 0))
          (when (< i (string-length s))
            (let ((ch (string-ref s i)))
              (when (pred ch) (write-char ch port)))
            (loop (+ i 1))))
        (get-output-string port)))

    (define (string-remove pred s)
      (string-filter (lambda (ch) (not (pred ch))) s))

    (define (string-take s n) (substring s 0 (min n (string-length s))))
    (define (string-drop s n) (substring s (min n (string-length s)) (string-length s)))

    (define (string-take-right s n)
      (let ((len (string-length s)))
        (substring s (max 0 (- len n)) len)))

    (define (string-drop-right s n)
      (let ((len (string-length s)))
        (substring s 0 (max 0 (- len n)))))

    (define (string-prefix? prefix s)
      (and (>= (string-length s) (string-length prefix))
           (string=? (substring s 0 (string-length prefix)) prefix)))

    (define (string-suffix? suffix s)
      (let ((slen (string-length s))
            (plen (string-length suffix)))
        (and (>= slen plen)
             (string=? (substring s (- slen plen) slen) suffix))))

    (define (min a b) (if (< a b) a b))
    (define (max a b) (if (> a b) a b))))
