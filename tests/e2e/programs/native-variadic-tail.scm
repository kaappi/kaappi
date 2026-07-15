; #1498: self-tail recursion in a VARIADIC function is now compiled as a loop
; (branch back to the body label) instead of a general recursive call, so it
; runs in bounded stack. Each iteration rebuilds the rest list from the args
; past the fixed arity; the 50000 iterations allocate ~100k cons cells, which
; triggers real garbage collection and exercises the rest-list rooting fix
; (the rebuilt spine must survive a GC that does not otherwise reference it).
;
; At n=0: acc = 50000, rest = (1 1) [from the last call (go 0 50000 1 1)], so
; car rest = 1 and (length rest) = 2, giving 50000 + 1 + 2 = 50003.
(define (go n acc . rest)
  (if (= n 0)
      (+ acc (car rest) (length rest))
      (go (- n 1) (+ acc 1) n n)))
(display (go 50000 0 0 0))
(newline)
