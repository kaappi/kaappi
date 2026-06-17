(define-library (srfi 14)
  (import (scheme base) (scheme char))
  (export char-set? char-set char-set-contains?
          char-set-adjoin char-set-delete
          char-set-union char-set-intersection char-set-difference
          char-set->list list->char-set
          char-set-fold char-set-for-each char-set-map
          char-set-filter char-set-count
          char-set:lower-case char-set:upper-case char-set:letter
          char-set:digit char-set:whitespace char-set:punctuation
          char-set:empty char-set:full)
  (begin
    (define-record-type <char-set>
      (make-char-set members)
      char-set?
      (members cs-members))

    (define (char-set . chars)
      (make-char-set chars))

    (define (char-set-contains? cs ch)
      (let check ((members (cs-members cs)))
        (if (null? members) #f
            (if (char=? (car members) ch) #t
                (check (cdr members))))))

    (define (char-set-adjoin cs . chars)
      (make-char-set (append (cs-members cs) chars)))

    (define (char-set-delete cs . chars)
      (make-char-set
        (let del ((members (cs-members cs)))
          (if (null? members) '()
              (if (memv (car members) chars)
                  (del (cdr members))
                  (cons (car members) (del (cdr members))))))))

    (define (char-set-union . sets)
      (make-char-set
        (let uni ((rest sets) (result '()))
          (if (null? rest) result
              (uni (cdr rest)
                   (append result
                     (let add ((members (cs-members (car rest))))
                       (if (null? members) '()
                           (if (memv (car members) result)
                               (add (cdr members))
                               (cons (car members) (add (cdr members))))))))))))

    (define (char-set-intersection cs1 cs2)
      (make-char-set
        (let isect ((members (cs-members cs1)))
          (if (null? members) '()
              (if (char-set-contains? cs2 (car members))
                  (cons (car members) (isect (cdr members)))
                  (isect (cdr members)))))))

    (define (char-set-difference cs1 cs2)
      (make-char-set
        (let diff ((members (cs-members cs1)))
          (if (null? members) '()
              (if (char-set-contains? cs2 (car members))
                  (diff (cdr members))
                  (cons (car members) (diff (cdr members))))))))

    (define (char-set->list cs) (cs-members cs))
    (define (list->char-set lst) (make-char-set lst))

    (define (char-set-fold proc init cs)
      (let fold ((members (cs-members cs)) (acc init))
        (if (null? members) acc
            (fold (cdr members) (proc (car members) acc)))))

    (define (char-set-for-each proc cs)
      (for-each proc (cs-members cs)))

    (define (char-set-map proc cs)
      (make-char-set (map proc (cs-members cs))))

    (define (char-set-filter pred cs)
      (make-char-set
        (let filt ((members (cs-members cs)))
          (if (null? members) '()
              (if (pred (car members))
                  (cons (car members) (filt (cdr members)))
                  (filt (cdr members)))))))

    (define (char-set-count pred cs)
      (char-set-fold (lambda (ch count) (if (pred ch) (+ count 1) count))
                     0 cs))

    (define (make-range-set from to)
      (define (go i result)
        (if (> i to) (make-char-set result)
            (go (+ i 1) (cons (integer->char i) result))))
      (go from '()))

    (define char-set:lower-case (make-range-set 97 122))
    (define char-set:upper-case (make-range-set 65 90))
    (define char-set:digit (make-range-set 48 57))
    (define char-set:letter (char-set-union char-set:lower-case char-set:upper-case))
    (define char-set:whitespace (char-set #\space #\tab #\newline #\return))
    (define char-set:punctuation
      (char-set #\! #\" #\# #\$ #\% #\& #\' #\( #\) #\* #\+ #\,
                #\- #\. #\/ #\: #\; #\< #\= #\> #\? #\@ #\[ #\\
                #\] #\^ #\_ #\` #\{ #\| #\} #\~))
    (define char-set:empty (char-set))
    (define char-set:full (make-range-set 0 127))))
