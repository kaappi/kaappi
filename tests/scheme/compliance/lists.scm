;;; R7RS List compliance tests
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "lists")

;; --- caar, cadr, cdar, cddr ---
(test-group "caar/cadr/cdar/cddr"
  (test-eqv "caar" 1 (caar '((1 2) 3)))
  (test-eqv "cadr" 2 (cadr '(1 2 3)))
  (test-equal "cdar" '(2) (cdar '((1 2) 3)))
  (test-equal "cddr" '(3) (cddr '(1 2 3))))

;; --- list-ref ---
(test-group "list-ref"
  (test-eq "list-ref index 0" 'a (list-ref '(a b c d) 0))
  (test-eq "list-ref index 2" 'c (list-ref '(a b c d) 2))
  (test-eq "list-ref index 3" 'd (list-ref '(a b c d) 3)))

;; --- list-tail ---
(test-group "list-tail"
  (test-equal "list-tail index 0" '(a b c d) (list-tail '(a b c d) 0))
  (test-equal "list-tail index 2" '(c d) (list-tail '(a b c d) 2))
  (test-equal "list-tail index 4" '() (list-tail '(a b c d) 4)))

;; --- list-set! ---
(test-group "list-set!"
  (test-equal "list-set! middle element"
    '(1 99 3)
    (let ((ls (list 1 2 3)))
      (list-set! ls 1 99)
      ls)))

;; --- list-copy ---
(test-group "list-copy"
  (test-equal "list-copy produces equal list"
    '(1 2 3)
    (list-copy (list 1 2 3)))
  (test-equal "list-copy is independent of original"
    '(1 2 3)
    (let ((original (list 1 2 3)))
      (let ((copy (list-copy original)))
        (list-set! copy 0 99)
        original)))
  (test-equal "list-copy mutation applies to copy"
    '(99 2 3)
    (let ((original (list 1 2 3)))
      (let ((copy (list-copy original)))
        (list-set! copy 0 99)
        copy))))

;; --- make-list ---
(test-group "make-list"
  (test-equal "make-list with fill" '(0 0 0) (make-list 3 0))
  (test-equal "make-list zero length" '() (make-list 0)))

;; --- member ---
(test-group "member"
  (test-equal "member found" '(3 4 5) (member 3 '(1 2 3 4 5)))
  (test-eqv "member not found" #f (member 6 '(1 2 3 4 5)))
  (test-equal "member with equal?" '((b) (c)) (member '(b) '((a) (b) (c)))))

;; --- memq ---
(test-group "memq"
  (test-equal "memq found" '(b c) (memq 'b '(a b c)))
  (test-eqv "memq not found" #f (memq 'd '(a b c))))

;; --- memv ---
(test-group "memv"
  (test-equal "memv found" '(2 3) (memv 2 '(1 2 3)))
  (test-eqv "memv not found" #f (memv 4 '(1 2 3))))

;; --- assoc ---
(test-group "assoc"
  (test-equal "assoc found" '(b 2) (assoc 'b '((a 1) (b 2) (c 3))))
  (test-eqv "assoc not found" #f (assoc 'd '((a 1) (b 2) (c 3)))))

;; --- assq ---
(test-group "assq"
  (test-equal "assq found" '(b 2) (assq 'b '((a 1) (b 2) (c 3))))
  (test-eqv "assq not found" #f (assq 'd '((a 1) (b 2) (c 3)))))

;; --- assv ---
(test-group "assv"
  (test-equal "assv found" '(2 b) (assv 2 '((1 a) (2 b) (3 c))))
  (test-eqv "assv not found" #f (assv 4 '((1 a) (2 b) (3 c)))))

;; --- boolean=? ---
(test-group "boolean=?"
  (test-assert "boolean=? #t #t" (boolean=? #t #t))
  (test-eqv "boolean=? #f #f" #t (boolean=? #f #f))
  (test-eqv "boolean=? #t #f" #f (boolean=? #t #f))
  (test-assert "boolean=? #t #t #t" (boolean=? #t #t #t)))

;; --- symbol=? ---
(test-group "symbol=?"
  (test-assert "symbol=? same" (symbol=? 'foo 'foo))
  (test-eqv "symbol=? different" #f (symbol=? 'foo 'bar)))

;; --- map ---
(test-group "map"
  (test-equal "map car" '(1 3 5) (map car '((1 2) (3 4) (5 6))))
  (test-equal "map square" '(1 4 9) (map (lambda (x) (* x x)) '(1 2 3)))
  (test-equal "map with two lists" '(11 22 33) (map + '(1 2 3) '(10 20 30)))
  (test-equal "map empty list" '() (map car '())))

;; --- for-each ---
(test-group "for-each"
  (test-equal "for-each collects" '(1 2 3)
    (let ((result '()))
      (for-each (lambda (x) (set! result (cons x result))) '(1 2 3))
      (reverse result)))
  (test-eqv "for-each multiple lists" 66
    (let ((sum 0))
      (for-each (lambda (a b) (set! sum (+ sum a b))) '(1 2 3) '(10 20 30))
      sum)))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "lists")
(if (> %test-fail-count 0) (exit 1))
