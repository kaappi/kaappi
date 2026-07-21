;; SRFI-168 (Generic Tuple Store Database) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi168.scm
;;
;; SRFI 168 is built directly on SRFI 167 (nstore stores tuples through an
;; engine's okvs/transaction, packing keys with engine-pack/unpack), so
;; these tests exercise that integration explicitly rather than assuming it.

(import (scheme base) (scheme process-context)
        (srfi 146 hash) (srfi 158) (srfi 167) (srfi 168) (srfi 64))

(test-begin "srfi-168")

;;; --- construction and predicates ---

(define engine (make-default-engine))
(define triplestore (nstore engine (list 0) '(subject predicate object)))
(test-equal #t (nstore? triplestore))
(test-equal #f (nstore? 42))

(define v (nstore-var 'title))
(test-equal #t (nstore-var? v))
(test-equal #f (nstore-var? 'title))
(test-equal 'title (nstore-var-name v))

;;; --- ask?/add!/delete! directly on an okvs (no explicit transaction) ---

(define db (okvs-open "test-nstore-db"))

(test-equal #f (nstore-ask? db triplestore (list "a" 'p "b")))
(nstore-add! db triplestore (list "a" 'p "b"))
(test-equal #t (nstore-ask? db triplestore (list "a" 'p "b")))
;; adding twice is a no-op, not an error
(nstore-add! db triplestore (list "a" 'p "b"))
(test-equal #t (nstore-ask? db triplestore (list "a" 'p "b")))

(nstore-delete! db triplestore (list "a" 'p "b"))
(test-equal #f (nstore-ask? db triplestore (list "a" 'p "b")))
;; deleting an absent tuple is a no-op, not an error
(nstore-delete! db triplestore (list "a" 'p "b"))
(test-equal #f (nstore-ask? db triplestore (list "a" 'p "b")))

;;; --- arity checking against the nstore's declared items ---

(test-equal #t (guard (e (#t #t)) (nstore-add! db triplestore (list "a" 'p)) #f))
(test-equal #t (guard (e (#t #t)) (nstore-ask? db triplestore (list "a" 'p "b" "c")) #f))
(test-equal #t (guard (e (#t #t)) (nstore-delete! db triplestore '()) #f))

;;; --- hooks (reusing SRFI 167's minimal hook object) ---

(define hook-log '())
(okvs-hook-add! (nstore-hook-on-add triplestore)
                (lambda (txn items) (set! hook-log (cons (cons 'add items) hook-log))))
(okvs-hook-add! (nstore-hook-on-delete triplestore)
                (lambda (txn items) (set! hook-log (cons (cons 'delete items) hook-log))))
(nstore-add! db triplestore (list "hook-subject" 'p "o"))
(nstore-delete! db triplestore (list "hook-subject" 'p "o"))
(test-equal (list (list 'delete "hook-subject" 'p "o") (list 'add "hook-subject" 'p "o"))
  hook-log)
(test-equal #t (okvs-hook? (nstore-hook-on-add triplestore)))

;;; --- pattern-based queries: nstore-select ---

(define (generator->pairs gen)
  (let loop ((acc '()))
    (let ((v (gen)))
      (if (eof-object? v) (reverse acc) (loop (cons v acc))))))

(nstore-add! db triplestore (list "alice" 'knows "bob"))
(nstore-add! db triplestore (list "alice" 'knows "carol"))
(nstore-add! db triplestore (list "bob" 'knows "carol"))
(nstore-add! db triplestore (list "alice" 'age 30))

;; no variables: exact-match probe, equivalent to nstore-ask?
(test-equal 1 (length (generator->pairs (nstore-select db triplestore (list "alice" 'age 30)))))
(test-equal 0 (length (generator->pairs (nstore-select db triplestore (list "alice" 'age 31)))))

;; a single variable: bindings come back ordered by that variable's value,
;; and each binding is a SRFI 146 hash-mapping keyed by the variable's name
(define alice-knows
  (generator->pairs (nstore-select db triplestore (list "alice" 'knows (nstore-var 'whom)))))
(test-equal 2 (length alice-knows))
(test-equal '("bob" "carol") (map (lambda (hm) (hashmap-ref hm 'whom)) alice-knows))

;; multiple variables in one pattern: matches scan in ascending (subject,
;; predicate, object) order regardless of which positions are variables
(define who-knows-carol
  (generator->pairs (nstore-select db triplestore (list (nstore-var 'who) 'knows "carol"))))
(test-equal '("alice" "bob") (map (lambda (hm) (hashmap-ref hm 'who)) who-knows-carol))

;; offset/limit config
(test-equal '("carol")
  (map (lambda (hm) (hashmap-ref hm 'whom))
       (generator->pairs (nstore-select db triplestore (list "alice" 'knows (nstore-var 'whom))
                                         (list (cons 'offset 1))))))
(test-equal '("bob")
  (map (lambda (hm) (hashmap-ref hm 'whom))
       (generator->pairs (nstore-select db triplestore (list "alice" 'knows (nstore-var 'whom))
                                         (list (cons 'limit 1))))))

;;; --- nstore-where / nstore-query: join-style composition ---

;; "who does alice know, that also knows carol?" -> bob (alice knows bob, bob knows carol)
(define friends-of-carol-via-alice
  (generator->pairs
    (nstore-query
      (nstore-select db triplestore (list "alice" 'knows (nstore-var 'whom)))
      (nstore-where db triplestore (list (nstore-var 'whom) 'knows "carol")))))
(test-equal 1 (length friends-of-carol-via-alice))
(test-equal "bob" (hashmap-ref (car friends-of-carol-via-alice) 'whom))

;;; --- worked example from the SRFI 168 document: a blog triplestore ---

(define blog-engine (make-default-engine))
(define (make-triplestore prefix) (nstore blog-engine prefix '(subject predicate object)))
(define blog-store (make-triplestore (list 0)))
(define blog-database (okvs-open "/data"))

(define (add-blog-post! transaction title body keywords)
  (nstore-add! transaction blog-store (list title 'post/body body))
  (let loop ((keywords keywords))
    (unless (null? keywords)
      (nstore-add! transaction blog-store (list title 'post/keyword (car keywords)))
      (loop (cdr keywords)))))

(okvs-in-transaction blog-database
  (lambda (transaction)
    (add-blog-post! transaction "Hello, world!" "First post." '(scheme))))

(okvs-in-transaction blog-database
  (lambda (transaction)
    (add-blog-post! transaction "okvs for the win"
                     "With okvs one can build powerful abstractions."
                     '(okvs scheme database))))

(okvs-in-transaction blog-database
  (lambda (transaction)
    (add-blog-post! transaction "Easy on-disk persistence"
                     "nstore is a database abstraction."
                     '(nstore scheme database))))

(okvs-in-transaction blog-database
  (lambda (transaction)
    (add-blog-post! transaction "hoply"
                     "hoply is an implementation in python."
                     '(nstore python database))))

(define query-result
  (okvs-in-transaction blog-database
    (lambda (transaction)
      (generator-map->list
        (lambda (binding) (hashmap-ref binding 'post/title))
        (nstore-query
          (nstore-select transaction blog-store
                         (list (nstore-var 'post/title) 'post/keyword 'scheme))
          (nstore-where transaction blog-store
                        (list (nstore-var 'post/title) 'post/keyword 'database)))))))

(test-equal '("Easy on-disk persistence" "okvs for the win") query-result)

;; the query is read-only: a fresh probe still finds all four posts present
(test-equal #t (nstore-ask? blog-database blog-store (list "hoply" 'post/body "hoply is an implementation in python.")))

(let ((runner (test-runner-current)))
  (test-end "srfi-168")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
