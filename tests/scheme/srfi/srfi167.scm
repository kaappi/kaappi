;; SRFI-167 (Ordered Key Value Store) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi167.scm

(import (scheme base) (scheme process-context) (srfi 69) (srfi 128) (srfi 167) (srfi 64))

(test-begin "srfi-167")

;;; --- construction and predicates ---

(define db (okvs-open "test-db"))
(test-equal #t (okvs? db))
(test-equal #f (okvs? 42))
(test-equal #t (engine? (make-default-engine)))
(test-equal #f (engine? 42))
(test-equal #f (okvs-transaction? db))

;;; --- ref/set!/delete! directly on an okvs (no explicit transaction) ---

(define k1 (string->utf8 "alpha"))
(define k2 (string->utf8 "beta"))
(define k3 (string->utf8 "gamma"))
(define v1 (string->utf8 "1"))
(define v2 (string->utf8 "2"))
(define v3 (string->utf8 "3"))

(test-equal #f (okvs-ref db k1))
(okvs-set! db k1 v1)
(test-equal v1 (okvs-ref db k1))
(okvs-set! db k2 v2)
(okvs-set! db k3 v3)
(test-equal v2 (okvs-ref db k2))

(okvs-delete! db k2)
(test-equal #f (okvs-ref db k2))
(okvs-set! db k2 v2) ;; restore for the range tests below

;;; --- ordered range scans ---

(define (generator->pairs gen)
  (let loop ((acc '()))
    (let ((v (gen)))
      (if (eof-object? v) (reverse acc) (loop (cons v acc))))))

(define (keys->strings pairs) (map (lambda (p) (utf8->string (car p))) pairs))
(define (vals->strings pairs) (map (lambda (p) (utf8->string (cdr p))) pairs))

(define all-pairs (generator->pairs (okvs-range db (string->utf8 "") #t (string->utf8 "~") #t)))
(test-equal 3 (length all-pairs))
(test-equal '("alpha" "beta" "gamma") (keys->strings all-pairs))
(test-equal '("1" "2" "3") (vals->strings all-pairs))

;; inclusive/exclusive bound combinations
(test-equal '("alpha" "beta")
  (keys->strings (generator->pairs (okvs-range db k1 #t k3 #f))))
(test-equal '("beta")
  (keys->strings (generator->pairs (okvs-range db k1 #f k3 #f))))
(test-equal '("alpha" "beta" "gamma")
  (keys->strings (generator->pairs (okvs-range db k1 #t k3 #t))))
(test-equal '()
  (keys->strings (generator->pairs (okvs-range db k1 #f k3 #t (list (cons 'limit 0))))))

;; config: reverse?, offset, limit (applied in that order per the spec)
(test-equal '("gamma" "beta" "alpha")
  (keys->strings (generator->pairs
                   (okvs-range db (string->utf8 "") #t (string->utf8 "~") #t
                               (list (cons 'reverse? #t))))))
(test-equal '("beta")
  (keys->strings (generator->pairs
                   (okvs-range db (string->utf8 "") #t (string->utf8 "~") #t
                               (list (cons 'offset 1) (cons 'limit 1))))))
(test-equal '("gamma" "beta")
  (keys->strings (generator->pairs
                   (okvs-range db (string->utf8 "") #t (string->utf8 "~") #t
                               (list (cons 'reverse? #t) (cons 'limit 2))))))

;;; --- prefix range ---

(okvs-set! db (string->utf8 "app-1") (string->utf8 "x"))
(okvs-set! db (string->utf8 "app-2") (string->utf8 "y"))
(okvs-set! db (string->utf8 "banana") (string->utf8 "z"))

(test-equal '("app-1" "app-2")
  (keys->strings (generator->pairs (okvs-prefix-range db (string->utf8 "app")))))
(test-equal 6 (length (generator->pairs (okvs-prefix-range db (string->utf8 "")))))
(test-equal '("app-2")
  (keys->strings (generator->pairs (okvs-prefix-range db (string->utf8 "app") (list (cons 'offset 1))))))

;;; --- range-remove! ---

(okvs-range-remove! db (string->utf8 "app-1") #t (string->utf8 "app-2") #t)
(test-equal #f (okvs-ref db (string->utf8 "app-1")))
(test-equal #f (okvs-ref db (string->utf8 "app-2")))
(test-equal (string->utf8 "z") (okvs-ref db (string->utf8 "banana")))

;;; --- transactions: commit ---

(define committed-result
  (okvs-in-transaction db
    (lambda (txn)
      (okvs-set! txn (string->utf8 "tx-key") (string->utf8 "tx-val"))
      'committed)))
(test-equal 'committed committed-result)
(test-equal (string->utf8 "tx-val") (okvs-ref db (string->utf8 "tx-key")))

;;; --- transactions: rollback on an escaping condition ---

(define failure-condition #f)
(define rollback-result
  (okvs-in-transaction db
    (lambda (txn)
      (okvs-set! txn (string->utf8 "rollback-key") (string->utf8 "should-not-persist"))
      (error "boom"))
    (lambda (condition) (set! failure-condition condition) 'rolled-back)))
(test-equal 'rolled-back rollback-result)
(test-equal #f (okvs-ref db (string->utf8 "rollback-key")))
(test-equal #t (error-object? failure-condition))

;; default failure handler is `raise`: an uncaught condition propagates
(test-equal #t
  (guard (e (#t #t))
    (okvs-in-transaction db (lambda (txn) (error "uncaught")))
    #f))

;;; --- a transaction sees its own writes before it commits ---

(okvs-in-transaction db
  (lambda (txn)
    (okvs-set! txn (string->utf8 "self-read") (string->utf8 "v"))
    (test-equal (string->utf8 "v") (okvs-ref txn (string->utf8 "self-read")))
    (test-equal #f (okvs-ref db (string->utf8 "self-read")))
    'ok))
(test-equal (string->utf8 "v") (okvs-ref db (string->utf8 "self-read")))

;;; --- transaction state ---

(okvs-in-transaction db
  (lambda (txn)
    (test-equal #t (okvs-transaction? txn))
    (test-equal #f (okvs-transaction? db))
    (hash-table-set! (okvs-transaction-state txn) 'note "hi")
    (test-equal "hi" (hash-table-ref (okvs-transaction-state txn) 'note))
    'ok))

;;; --- hooks ---

(define hook-log '())
(okvs-hook-add! (okvs-hook-on-transaction-begin db)
                (lambda (txn) (set! hook-log (cons 'begin hook-log))))
(okvs-hook-add! (okvs-hook-on-transaction-commit db)
                (lambda (txn) (set! hook-log (cons 'commit hook-log))))
(okvs-in-transaction db (lambda (txn) 'ok))
(test-equal '(commit begin) hook-log)
(test-equal #t (okvs-hook? (okvs-hook-on-transaction-begin db)))

;;; --- make-default-engine delegation to the same okvs/transaction machinery ---

(define eng (make-default-engine))
(define db2 (engine-open eng "test-db-2"))
(test-equal #t (okvs? db2))
(engine-set! eng db2 (string->utf8 "e1") (string->utf8 "v1"))
(test-equal (string->utf8 "v1") (engine-ref eng db2 (string->utf8 "e1")))
(engine-delete! eng db2 (string->utf8 "e1"))
(test-equal #f (engine-ref eng db2 (string->utf8 "e1")))

(engine-in-transaction eng db2
  (lambda (txn) (engine-set! eng txn (string->utf8 "e2") (string->utf8 "v2"))))
(test-equal (string->utf8 "v2") (engine-ref eng db2 (string->utf8 "e2")))

(engine-set! eng db2 (string->utf8 "r1") (string->utf8 "a"))
(engine-set! eng db2 (string->utf8 "r2") (string->utf8 "b"))
(test-equal '("r1" "r2")
  (keys->strings (generator->pairs
                   (engine-range eng db2 (string->utf8 "r") #t (string->utf8 "s") #t))))
(test-equal '("r1" "r2")
  (keys->strings (generator->pairs (engine-prefix-range eng db2 (string->utf8 "r")))))
(engine-range-remove! eng db2 (string->utf8 "r1") #t (string->utf8 "r2") #t)
(test-equal #f (engine-ref eng db2 (string->utf8 "r1")))

(test-equal #t (okvs-hook? (engine-hook-on-transaction-begin eng db2)))
(test-equal #t (okvs-hook? (engine-hook-on-transaction-commit eng db2)))

;;; --- engine-pack / engine-unpack: round trip ---

(test-equal '(#f) (engine-unpack eng (engine-pack eng #f)))
(test-equal '(#t) (engine-unpack eng (engine-pack eng #t)))
(test-equal '(0) (engine-unpack eng (engine-pack eng 0)))
(test-equal '(42) (engine-unpack eng (engine-pack eng 42)))
(test-equal '(-42) (engine-unpack eng (engine-pack eng -42)))
(test-equal '(-1) (engine-unpack eng (engine-pack eng -1)))
(test-equal '(1000000) (engine-unpack eng (engine-pack eng 1000000)))
(test-equal '("hello") (engine-unpack eng (engine-pack eng "hello")))
(test-equal '("") (engine-unpack eng (engine-pack eng "")))
(test-equal (list (string #\a (integer->char 0) #\b))
  (engine-unpack eng (engine-pack eng (string #\a (integer->char 0) #\b))))
(test-equal '(greeting) (engine-unpack eng (engine-pack eng 'greeting)))
(test-equal '() (engine-unpack eng (engine-pack eng)))
(test-equal '("a" b 3 #t #f -7)
  (engine-unpack eng (engine-pack eng "a" 'b 3 #t #f -7)))

;;; --- engine-pack: encoded order matches value order (same-type items) ---

(define bv<? (comparator-ordering-predicate (make-default-comparator)))
(define (pack-one x) (engine-pack eng x))

(test-equal #t (bv<? (pack-one #f) (pack-one #t)))
(test-equal #t (bv<? (pack-one -100) (pack-one 0)))
(test-equal #t (bv<? (pack-one 0) (pack-one 1)))
(test-equal #t (bv<? (pack-one -5) (pack-one -1)))
(test-equal #t (bv<? (pack-one 5) (pack-one 100)))
(test-equal #t (bv<? (pack-one -1000) (pack-one -999)))
(test-equal #t (bv<? (pack-one 255) (pack-one 256)))
(test-equal #t (bv<? (pack-one "a") (pack-one "ab")))
(test-equal #t (bv<? (pack-one "ab") (pack-one "b")))
(test-equal #t (bv<? (pack-one "apple") (pack-one "banana")))
(test-equal #t (bv<? (pack-one 'apple) (pack-one 'banana)))

;; unsupported types signal an error rather than silently miscompiling a key
(test-equal #t (guard (e (#t #t)) (engine-pack eng 3.14) #f))
(test-equal #t (guard (e (#t #t)) (engine-pack eng (list 1 2)) #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-167")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
