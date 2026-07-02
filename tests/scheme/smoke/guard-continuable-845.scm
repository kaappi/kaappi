;; Regression test for #845: guard re-raises unmatched conditions with
;; raise instead of raise-continuable

;; Non-continuable raise through non-matching guard should work
(display
 (guard (outer-c (#t 'caught))
   (guard (c (#f #f))
     (raise 'boom))))
(newline)

;; raise-continuable through non-matching guard should not crash
(display
 (with-exception-handler
   (lambda (e) 100)
   (lambda ()
     (guard (c (#f #f))
       (raise-continuable 'x)))))
(newline)
