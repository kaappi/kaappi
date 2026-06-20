# Tips

- **Tail calls are optimized.** Write loops as recursive calls without worrying
  about stack overflow:

  ```scheme
  (define (loop n) (loop (+ n 1)))  ;; runs forever, no stack growth
  ```

- **Bignum arithmetic is automatic.** When a fixnum operation would overflow
  63 bits, the result is promoted to a bignum:

  ```scheme
  (expt 2 100)  ;=> 1267650600228229401496703205376
  ```

- **Unicode works everywhere.** String indexing, character predicates, and case
  conversion all operate on Unicode codepoints:

  ```scheme
  (char-alphabetic? #\λ)         ;=> #t
  (string-upcase "straße")       ;=> "STRASSE"
  ```

- **Use `guard` for structured error handling.** It combines exception catching
  with pattern matching:

  ```scheme
  (guard (e (#t (display "error caught\n")))
    (/ 1 0))
  ```
