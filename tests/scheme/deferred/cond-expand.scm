;; cond-expand tests
(display (cond-expand
  (r7rs 'r7rs-supported)
  (else 'not-r7rs)))
(newline)

(display (cond-expand
  (kaappi 'kaappi-impl)
  (else 'other)))
(newline)

(display (cond-expand
  ((library (scheme base)) 'has-scheme-base)
  (else 'no-scheme-base)))
(newline)
