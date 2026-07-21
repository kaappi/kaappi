;; SRFI-234 (Topological Sorting) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi234.scm

(import (scheme base) (scheme process-context) (srfi 234) (srfi 11) (srfi 64))

(define (list-index lst val)
  (let loop ((i 0) (l lst))
    (cond ((null? l) -1)
          ((equal? (car l) val) i)
          (else (loop (+ i 1) (cdr l))))))

(test-begin "srfi-234")

;;; --- topological-sort ---
(test-equal "topological-sort: simple linear"
  '(a b c)
  (topological-sort '((a b) (b c))))

(test-equal "topological-sort: diamond"
  ;; a -> b, a -> c, b -> d, c -> d
  ;; valid: a before b/c, b/c before d
  (let ((result (topological-sort '((a b c) (b d) (c d)))))
    (and (list? result)
         (= (length result) 4)
         (< (list-index result 'a) (list-index result 'b))
         (< (list-index result 'a) (list-index result 'c))
         (< (list-index result 'b) (list-index result 'd))
         (< (list-index result 'c) (list-index result 'd))))
  #t)

(test-equal "topological-sort: empty graph"
  '()
  (topological-sort '()))

(test-equal "topological-sort: single node no edges"
  '(a)
  (topological-sort '((a))))

;;; --- topological-sort/details ---
(test-assert "topological-sort/details: cycle detection"
  (let-values (((result msg cycle) (topological-sort/details '((a b) (b a)))))
    (and (not result) (string? msg))))

(test-assert "topological-sort/details: success returns #f for msg and cycle"
  (let-values (((result msg cycle) (topological-sort/details '((a b) (b c)))))
    (and (list? result) (not msg) (not cycle))))

;;; --- edgelist->graph ---
(test-equal "edgelist->graph: basic"
  '((a b c) (b e))
  (edgelist->graph '((a b) (a c) (b e))))

(test-equal "edgelist->graph: empty"
  '()
  (edgelist->graph '()))

;;; --- graph->edgelist ---
(test-equal "graph->edgelist: basic"
  '((a b) (a c) (b e))
  (graph->edgelist '((a b c) (b e))))

;;; --- edgelist/inverted->graph ---
(test-equal "edgelist/inverted->graph: basic"
  '((a b c) (b e))
  (edgelist/inverted->graph '((b a) (c a) (e b))))

;;; --- graph->edgelist/inverted ---
(test-equal "graph->edgelist/inverted: basic"
  '((b a) (c a) (e b))
  (graph->edgelist/inverted '((a b c) (b e))))

;;; --- connected-components ---
(test-assert "connected-components: two components"
  (let ((comps (connected-components '((a b) (b a) (c d) (d c)))))
    (and (= (length comps) 2)
         (or (and (member 'a (car comps)) (member 'b (car comps)))
             (and (member 'c (car comps)) (member 'd (car comps)))))))

;;; --- roundtrip: edgelist -> graph -> edgelist ---
(test-equal "roundtrip: edgelist->graph->edgelist"
  '((a b) (a c) (b e))
  (graph->edgelist (edgelist->graph '((a b) (a c) (b e)))))

(let ((runner (test-runner-current)))
  (test-end "srfi-234")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
