;; SRFI-116 (immutable list library) conformance tests — audit Phase 3b
;; Kaappi implements ilists as ordinary lists; these tests cover the
;; behavioral surface of the exported subset.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi116.scm

(import (scheme base) (srfi 116) (chibi test))

(test-begin "srfi-116")

;;; --- constructors and accessors ---
(test 1 (icar (ipair 1 2)))
(test 2 (icdr (ipair 1 2)))
(test 'a (icar (ilist 'a 'b 'c)))
(test '(b c) (ilist->list (icdr (ilist 'a 'b 'c))))
(test 3 (ilength (ilist 1 2 3)))
(test 0 (ilength inull))
(test #t (inull? inull))
(test #f (inull? (ilist 1)))
(test #t (ipair? (ipair 1 2)))
(test #t (ilist? (ilist 1 2)))

;; ipair* (like cons*)
(test 1 (icar (ipair* 1 2 3)))

;; nested accessors
(test 'b (icadr (ilist 'a 'b 'c)))
(test 'a (icaar (ilist (ilist 'a) 'b)))

;;; --- indexing ---
(test 'c (ilist-ref (ilist 'a 'b 'c) 2))
(test '(c) (ilist->list (ilist-tail (ilist 'a 'b 'c) 2)))

;;; --- transformations ---
(test '(3 2 1) (ilist->list (ireverse (ilist 1 2 3))))
(test '(1 2 3 4) (ilist->list (iappend (ilist 1 2) (ilist 3 4))))
(test '(2 4 6) (ilist->list (imap (lambda (x) (* 2 x)) (ilist 1 2 3))))
(test '(2) (ilist->list (ifilter even? (ilist 1 2 3))))
(test '(1 3) (ilist->list (iremove even? (ilist 1 2 3))))
(test 6 (ifold + 0 (ilist 1 2 3)))
(test '(1 2 3) (ilist->list (ifold-right ipair inull (ilist 1 2 3))))

;;; --- searching ---
(test 2 (ifind even? (ilist 1 2 3)))
(test #f (ifind even? (ilist 1 3 5)))
(test #t (iany even? (ilist 1 2)))
(test #f (ievery even? (ilist 1 2)))

;;; --- conversions round trip ---
(test '(1 2 3) (ilist->list (list->ilist '(1 2 3))))

;;; --- ifor-each order ---
(test '(a b c)
      (let ((acc '()))
        (ifor-each (lambda (x) (set! acc (cons x acc))) (ilist 'a 'b 'c))
        (reverse acc)))

(test-end "srfi-116")
