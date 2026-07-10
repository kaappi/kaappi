;; SRFI-116 (immutable list library) conformance tests — audit Phase 3b
;; Kaappi implements ilists as ordinary lists; these tests cover the
;; behavioral surface of the exported subset.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi116.scm

(import (scheme base) (srfi 116) (scheme process-context) (srfi 64))

(test-begin "srfi-116")

;;; --- constructors and accessors ---
(test-equal 1 (icar (ipair 1 2)))
(test-equal 2 (icdr (ipair 1 2)))
(test-equal 'a (icar (ilist 'a 'b 'c)))
(test-equal '(b c) (ilist->list (icdr (ilist 'a 'b 'c))))
(test-equal 3 (ilength (ilist 1 2 3)))
(test-equal 0 (ilength inull))
(test-equal #t (inull? inull))
(test-equal #f (inull? (ilist 1)))
(test-equal #t (ipair? (ipair 1 2)))
(test-equal #t (ilist? (ilist 1 2)))

;; ipair* (like cons*)
(test-equal 1 (icar (ipair* 1 2 3)))

;; nested accessors
(test-equal 'b (icadr (ilist 'a 'b 'c)))
(test-equal 'a (icaar (ilist (ilist 'a) 'b)))

;;; --- indexing ---
(test-equal 'c (ilist-ref (ilist 'a 'b 'c) 2))
(test-equal '(c) (ilist->list (ilist-tail (ilist 'a 'b 'c) 2)))

;;; --- transformations ---
(test-equal '(3 2 1) (ilist->list (ireverse (ilist 1 2 3))))
(test-equal '(1 2 3 4) (ilist->list (iappend (ilist 1 2) (ilist 3 4))))
(test-equal '(2 4 6) (ilist->list (imap (lambda (x) (* 2 x)) (ilist 1 2 3))))
(test-equal '(2) (ilist->list (ifilter even? (ilist 1 2 3))))
(test-equal '(1 3) (ilist->list (iremove even? (ilist 1 2 3))))
(test-equal 6 (ifold + 0 (ilist 1 2 3)))
(test-equal '(1 2 3) (ilist->list (ifold-right ipair inull (ilist 1 2 3))))

;;; --- searching ---
(test-equal 2 (ifind even? (ilist 1 2 3)))
(test-equal #f (ifind even? (ilist 1 3 5)))
(test-equal #t (iany even? (ilist 1 2)))
(test-equal #f (ievery even? (ilist 1 2)))

;;; --- conversions round trip ---
(test-equal '(1 2 3) (ilist->list (list->ilist '(1 2 3))))

;;; --- ifor-each order ---
(test-equal '(a b c)
            (let ((acc '()))
              (ifor-each (lambda (x) (set! acc (cons x acc))) (ilist 'a 'b 'c))
              (reverse acc)))

(let ((runner (test-runner-current)))
  (test-end "srfi-116")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
