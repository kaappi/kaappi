(define-library (srfi 234)
  (import (scheme base) (scheme case-lambda)
          (srfi 1) (srfi 11) (srfi 26))
  (export topological-sort
          topological-sort/details
          edgelist->graph
          edgelist/inverted->graph
          graph->edgelist
          graph->edgelist/inverted
          connected-components)
  (begin
    (define topological-sort
      (case-lambda
        ((graph) (topological-sort-impl graph equal? #f))
        ((graph eq) (topological-sort-impl graph eq #f))
        ((graph eq nodes) (topological-sort-impl graph eq nodes))))

    (define topological-sort/details
      (case-lambda
        ((graph) (topological-sort-impl/details graph equal? #f))
        ((graph eq) (topological-sort-impl/details graph eq #f))
        ((graph eq nodes) (topological-sort-impl/details graph eq nodes))))

    (define (topological-sort-impl graph eq nodes)
      (let-values (((v0 v1 v2)
                    (topological-sort-impl/details graph eq nodes)))
        v0))

    (define (topological-sort-impl/details graph eq nodes)
      (define table (map (lambda (n) (cons (car n) 0)) graph))
      (define queue '())
      (define result '())

      (define (set-up)
        (for-each
          (lambda (node)
            (for-each
              (lambda (to)
                (define p (assoc to table eq))
                (if p
                    (set-cdr! p (+ 1 (cdr p)))
                    (set! table (cons (cons to 1) table))))
              (cdr node)))
          graph))

      (define (traverse)
        (unless (null? queue)
          (let ((n0 (assoc (car queue) graph eq)))
            (set! queue (cdr queue))
            (when n0
              (for-each
                (lambda (to)
                  (define p (assoc to table eq))
                  (when p
                    (let ((cnt (- (cdr p) 1)))
                      (when (= cnt 0)
                        (set! result (cons to result))
                        (set! queue (cons to queue)))
                      (set-cdr! p cnt))))
                (cdr n0)))
            (traverse))))

      (set-up)
      (set! queue
        (apply append
               (map (lambda (p)
                      (if (= (cdr p) 0) (list (car p)) '()))
                    table)))
      (set! result queue)
      (traverse)
      (let ((rest (filter (lambda (e) (not (zero? (cdr e)))) table)))
        (if (null? rest)
            (values
              (if nodes
                  (let loop ((res '()) (result result))
                    (if (null? result) res
                        (loop (cons (vector-ref nodes (car result)) res)
                              (cdr result))))
                  (reverse result))
              #f #f)
            (values #f "graph has circular dependency" (map car rest)))))

    (define (connected-components graph)
      (define graph/inverted (edgelist->graph (graph->edgelist/inverted graph)))
      (define visited '())
      (define vertex-list '())
      (define (visit! node)
        (cond ((member node visited) '())
              (else
                (set! visited (cons node visited))
                (let ((node-in-graph (assoc node graph)))
                  (when node-in-graph
                    (for-each visit! (cdr node-in-graph))))
                (set! vertex-list (cons node vertex-list)))))
      (define in-component '())
      (define components '())
      (define (assign! u root)
        (unless (member u in-component)
          (set! in-component (cons u in-component))
          (set! components (cons (cons u (car components)) (cdr components)))
          (let ((node-in-graph (assoc u graph/inverted)))
            (when node-in-graph
              (for-each (cut assign! <> root) (cdr node-in-graph))))))
      (define (assign-as-component! u)
        (unless (member u in-component)
          (set! components (cons '() components))
          (assign! u u)))
      (for-each (lambda (g) (for-each visit! g)) graph)
      (for-each assign-as-component! vertex-list)
      components)

    (define edgelist->graph
      (case-lambda
        ((edgelist) (edgelist->graph-impl edgelist assoc))
        ((edgelist asc) (edgelist->graph-impl edgelist asc))))

    (define (edgelist->graph-impl edgelist asc)
      (let loop ((graph '()) (edges edgelist))
        (cond
          ((null? edges) (reverse graph))
          ((asc (car (car edges)) graph)
           (let* ((edge (car edges))
                  (left (car edge))
                  (graph-entry (asc left graph))
                  (right (car (cdr edge))))
             (let lp ((entry graph-entry))
               (if (null? (cdr entry))
                   (set-cdr! entry (list right))
                   (lp (cdr entry))))
             (loop graph (cdr edges))))
          (else (loop (cons (list (car (car edges)) (car (cdr (car edges)))) graph)
                      (cdr edges))))))

    (define edgelist/inverted->graph
      (case-lambda
        ((edgelist) (edgelist/inverted->graph-impl edgelist assoc))
        ((edgelist asc) (edgelist/inverted->graph-impl edgelist asc))))

    (define (edgelist/inverted->graph-impl edgelist asc)
      (let loop ((graph '()) (edges edgelist))
        (cond
          ((null? edges) (reverse graph))
          ((asc (car (cdr (car edges))) graph)
           (let* ((edge (car edges))
                  (left (car (cdr edge)))
                  (graph-entry (asc left graph))
                  (right (car edge)))
             (let lp ((entry graph-entry))
               (if (null? (cdr entry))
                   (set-cdr! entry (list right))
                   (lp (cdr entry))))
             (loop graph (cdr edges))))
          (else (loop (cons (list (car (cdr (car edges))) (car (car edges))) graph)
                      (cdr edges))))))

    (define (graph->edgelist graph)
      (graph->edgelist/base graph
        (lambda (top) (list (car top) (car (cdr top))))))

    (define (graph->edgelist/inverted graph)
      (graph->edgelist/base graph
        (lambda (top) (list (car (cdr top)) (car top)))))

    (define (graph->edgelist/base graph top-to-edge-fun)
      (let loop ((edgelist '()) (graph graph))
        (cond ((null? graph) (reverse edgelist))
              ((null? (car graph)) (loop edgelist (cdr graph)))
              ((null? (cdr (car graph))) (loop edgelist (cdr graph)))
              (else
                (let* ((top (car graph))
                       (edge (top-to-edge-fun top))
                       (rest (cdr (cdr top))))
                  (loop (cons edge edgelist)
                        (cons (cons (car top) rest) (cdr graph))))))))))
