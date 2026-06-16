(define-library (srfi 117)
  (import (scheme base))
  (export make-list-queue list-queue list-queue? list-queue-empty?
          list-queue-front list-queue-back
          list-queue-add-front! list-queue-add-back!
          list-queue-remove-front! list-queue-remove-back!
          list-queue-list list-queue-first-last
          list-queue-append list-queue-append!
          list-queue-concatenate
          list-queue-map list-queue-for-each)
  (begin
    (define-record-type <list-queue>
      (%make-list-queue front back)
      list-queue?
      (front lq-front set-lq-front!)
      (back lq-back set-lq-back!))

    (define (make-list-queue lst)
      (if (null? lst) (%make-list-queue '() '())
          (let loop ((l lst))
            (if (null? (cdr l))
                (%make-list-queue lst l)
                (loop (cdr l))))))

    (define (list-queue . elts) (make-list-queue elts))

    (define (list-queue-empty? q) (null? (lq-front q)))

    (define (list-queue-front q)
      (if (null? (lq-front q)) (error "list-queue-front: empty")
          (car (lq-front q))))

    (define (list-queue-back q)
      (if (null? (lq-back q)) (error "list-queue-back: empty")
          (car (lq-back q))))

    (define (list-queue-add-front! q elem)
      (let ((new-pair (list elem)))
        (if (null? (lq-front q))
            (begin (set-lq-front! q new-pair) (set-lq-back! q new-pair))
            (begin (set-cdr! new-pair (lq-front q))
                   (set-lq-front! q new-pair)))))

    (define (list-queue-add-back! q elem)
      (let ((new-pair (list elem)))
        (if (null? (lq-front q))
            (begin (set-lq-front! q new-pair) (set-lq-back! q new-pair))
            (begin (set-cdr! (lq-back q) new-pair)
                   (set-lq-back! q new-pair)))))

    (define (list-queue-remove-front! q)
      (if (null? (lq-front q)) (error "list-queue-remove-front!: empty")
          (let ((val (car (lq-front q))))
            (set-lq-front! q (cdr (lq-front q)))
            (if (null? (lq-front q)) (set-lq-back! q '()))
            val)))

    (define (list-queue-remove-back! q)
      (if (null? (lq-front q)) (error "list-queue-remove-back!: empty")
          (if (eq? (lq-front q) (lq-back q))
              (let ((val (car (lq-front q))))
                (set-lq-front! q '()) (set-lq-back! q '()) val)
              (let loop ((prev (lq-front q)))
                (if (eq? (cdr prev) (lq-back q))
                    (let ((val (car (lq-back q))))
                      (set-cdr! prev '()) (set-lq-back! q prev) val)
                    (loop (cdr prev)))))))

    (define (list-queue-list q) (lq-front q))
    (define (list-queue-first-last q) (values (lq-front q) (lq-back q)))

    (define (list-queue-append . queues)
      (make-list-queue (apply append (map list-queue-list queues))))

    (define (list-queue-append! . queues)
      (apply list-queue-append queues))

    (define (list-queue-concatenate queues)
      (apply list-queue-append queues))

    (define (list-queue-map f q)
      (make-list-queue (map f (list-queue-list q))))

    (define (list-queue-for-each f q)
      (for-each f (list-queue-list q)))))
