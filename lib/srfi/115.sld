(define-library (srfi 115)
  (import (scheme base) (scheme char) (scheme case-lambda) (scheme cxr))
  (export regexp regexp? regexp-matches? regexp-matches regexp-search
          regexp-match? regexp-match-count regexp-match-submatch
          regexp-match-submatch-start regexp-match-submatch-end regexp-match->list
          regexp->sre valid-sre?
          regexp-fold regexp-extract regexp-split regexp-partition
          regexp-replace regexp-replace-all)
  (begin

    (define-record-type <regexp>
      (%make-regexp sre compiled num-groups)
      regexp?
      (sre %regexp-sre)
      (compiled %regexp-compiled)
      (num-groups %regexp-num-groups))

    (define-record-type <regexp-match>
      (%make-regexp-match str groups)
      regexp-match?
      (str %match-str)
      (groups %match-groups))

    (define %sym-arrow (string->symbol "->"))
    (define (%char-word? c) (or (char-alphabetic? c) (char-numeric? c) (char=? c #\_)))
    (define (%cm a b cf) (if cf (char=? (char-downcase a) (char-downcase b)) (char=? a b)))

    ;;; Compile SRE to data structure
    (define (%csre sre gc)
      (cond
        ((string? sre) (list 'lit sre))
        ((char? sre) (list 'chr sre))
        ((and (symbol? sre) (memq sre '(bos eos bol eol bow eow))) (list 'assert sre))
        ((eq? sre 'any) (list 'any))
        ((eq? sre 'nonl) (list 'nonl))
        ((symbol? sre) (list 'class sre))
        ((not (pair? sre)) (error "regexp: invalid SRE" sre))
        (else (%csre-pair sre gc))))

    (define (%csre-pair sre gc)
      (let ((h (car sre)))
        (cond
          ((or (eq? h 'seq) (eq? h ':)) (cons 'seq (%map-csre (cdr sre) gc)))
          ((eq? h 'or) (cons 'alt (%map-csre (cdr sre) gc)))
          ((or (eq? h '?) (eq? h 'optional)) (list 'opt (%cbody (cdr sre) gc)))
          ((or (eq? h '*) (eq? h 'zero-or-more)) (list 'star (%cbody (cdr sre) gc)))
          ((or (eq? h '+) (eq? h 'one-or-more)) (list 'plus (%cbody (cdr sre) gc)))
          (else (%csre-pair2 sre gc)))))

    (define (%csre-pair2 sre gc)
      (let ((h (car sre)))
        (cond
          ((or (eq? h '=) (eq? h 'exactly)) (list 'exactly (cadr sre) (%cbody (cddr sre) gc)))
          ((or (eq? h '>=) (eq? h 'at-least)) (list 'at-least (cadr sre) (%cbody (cddr sre) gc)))
          ((or (eq? h '**) (eq? h 'repeated)) (list 'repeat (cadr sre) (caddr sre) (%cbody (cdddr sre) gc)))
          ((or (eq? h '$) (eq? h 'submatch))
           (let ((gn (car gc))) (set-car! gc (+ gn 1)) (list 'group gn (%cbody (cdr sre) gc))))
          ((or (eq? h %sym-arrow) (eq? h 'submatch-named))
           (let ((gn (car gc))) (set-car! gc (+ gn 1)) (list 'group gn (%cbody (cddr sre) gc))))
          (else (%csre-pair3 sre gc)))))

    (define (%csre-pair3 sre gc)
      (let ((h (car sre)))
        (cond
          ((eq? h 'w/nocase) (list 'nocase (%cbody (cdr sre) gc)))
          ((eq? h 'w/case) (list 'case (%cbody (cdr sre) gc)))
          ((or (eq? h '/) (eq? h 'char-range)) (list 'range (%build-ranges (cdr sre))))
          ((eq? h 'char-set) (list 'chars (cadr sre)))
          ((or (eq? h '~) (eq? h 'complement)) (list 'compl (%cbody (cdr sre) gc)))
          ((eq? h 'look-ahead) (list 'look (%cbody (cdr sre) gc)))
          ((eq? h 'neg-look-ahead) (list 'neglook (%cbody (cdr sre) gc)))
          ((eq? h 'word) (list 'seq (list 'assert 'bow) (%cbody (cdr sre) gc) (list 'assert 'eow)))
          ((or (eq? h 'w/nocapture) (eq? h 'w/ascii) (eq? h 'w/unicode)) (%cbody (cdr sre) gc))
          (else (error "regexp: unknown SRE" h)))))

    (define (%map-csre lst gc)
      (if (null? lst) '()
          (cons (%csre (car lst) gc) (%map-csre (cdr lst) gc))))

    (define (%cbody sres gc)
      (if (null? (cdr sres)) (%csre (car sres) gc)
          (cons 'seq (%map-csre sres gc))))

    (define (%build-ranges specs)
      (let loop ((specs specs) (ranges '()))
        (if (null? specs) ranges
            (let ((spec (car specs)))
              (if (string? spec)
                  (let sloop ((i 0) (r ranges))
                    (if (>= (+ i 1) (string-length spec)) (loop (cdr specs) r)
                        (sloop (+ i 2)
                               (cons (cons (char->integer (string-ref spec i))
                                           (char->integer (string-ref spec (+ i 1)))) r))))
                  (loop (cdr specs) ranges))))))

    ;;; Match interpreter — split into small functions

    (define (%run-lit s str pos end cf)
      (let ((slen (string-length s)))
        (if (> (+ pos slen) end) #f
            (let loop ((i 0))
              (if (= i slen) (+ pos slen)
                  (if (%cm (string-ref str (+ pos i)) (string-ref s i) cf)
                      (loop (+ i 1)) #f))))))

    (define (%match-class c name)
      (cond
        ((or (eq? name 'alphabetic) (eq? name 'alpha)) (char-alphabetic? c))
        ((or (eq? name 'numeric) (eq? name 'num)) (char-numeric? c))
        ((or (eq? name 'lower-case) (eq? name 'lower)) (char-lower-case? c))
        ((or (eq? name 'upper-case) (eq? name 'upper)) (char-upper-case? c))
        ((or (eq? name 'whitespace) (eq? name 'white) (eq? name 'space)) (char-whitespace? c))
        ((or (eq? name 'alphanumeric) (eq? name 'alphanum) (eq? name 'alnum))
         (or (char-alphabetic? c) (char-numeric? c)))
        ((or (eq? name 'punctuation) (eq? name 'punct))
         (and (not (char-alphabetic? c)) (not (char-numeric? c))
              (not (char-whitespace? c)) (>= (char->integer c) 33) (<= (char->integer c) 126)))
        ((eq? name 'word) (%char-word? c))
        ((or (eq? name 'hex-digit) (eq? name 'xdigit))
         (or (char-numeric? c) (and (char>=? (char-downcase c) #\a) (char<=? (char-downcase c) #\f))))
        ((eq? name 'ascii) (<= (char->integer c) 127))
        ((or (eq? name 'control) (eq? name 'cntrl)) (< (char->integer c) 32))
        ((or (eq? name 'graphic) (eq? name 'graph))
         (and (not (char-whitespace? c)) (>= (char->integer c) 33)))
        ((or (eq? name 'printing) (eq? name 'print)) (>= (char->integer c) 32))
        (else #f)))

    (define (%run-assert kind str pos end)
      (cond
        ((eq? kind 'bos) (= pos 0))
        ((eq? kind 'eos) (= pos end))
        ((eq? kind 'bol) (or (= pos 0) (char=? (string-ref str (- pos 1)) #\newline)))
        ((eq? kind 'eol) (or (= pos end) (char=? (string-ref str pos) #\newline)))
        ((eq? kind 'bow) (and (or (= pos 0) (not (%char-word? (string-ref str (- pos 1)))))
                              (< pos end) (%char-word? (string-ref str pos))))
        ((eq? kind 'eow) (and (> pos 0) (%char-word? (string-ref str (- pos 1)))
                              (or (= pos end) (not (%char-word? (string-ref str pos))))))
        (else #f)))

    (define (%run-seq parts str pos end groups cf)
      (if (null? parts) (cons pos groups)
          (let ((r (%run (car parts) str pos end groups cf)))
            (if r (%run-seq (cdr parts) str (car r) end (cdr r) cf) #f))))

    (define (%run-alt parts str pos end groups cf)
      (if (null? parts) #f
          (let ((r (%run (car parts) str pos end groups cf)))
            (if r r (%run-alt (cdr parts) str pos end groups cf)))))

    (define (%run-star inner str pos end groups cf)
      (let ((r (%run inner str pos end groups cf)))
        (if (and r (> (car r) pos))
            (%run-star inner str (car r) end (cdr r) cf)
            (cons pos groups))))

    (define (%run-plus inner str pos end groups cf)
      (let ((first (%run inner str pos end groups cf)))
        (if (not first) #f (%run-star inner str (car first) end (cdr first) cf))))

    (define (%run-exactly n inner str pos end groups cf)
      (if (= n 0) (cons pos groups)
          (let ((r (%run inner str pos end groups cf)))
            (if r (%run-exactly (- n 1) inner str (car r) end (cdr r) cf) #f))))

    (define (%run-at-least n inner str pos end groups cf)
      (if (> n 0)
          (let ((r (%run inner str pos end groups cf)))
            (if r (%run-at-least (- n 1) inner str (car r) end (cdr r) cf) #f))
          (%run-star inner str pos end groups cf)))

    (define (%run-repeat i lo hi inner str pos end groups cf)
      (cond
        ((= i hi) (cons pos groups))
        ((< i lo)
         (let ((r (%run inner str pos end groups cf)))
           (if r (%run-repeat (+ i 1) lo hi inner str (car r) end (cdr r) cf) #f)))
        (else
         (let ((r (%run inner str pos end groups cf)))
           (if (and r (> (car r) pos))
               (%run-repeat (+ i 1) lo hi inner str (car r) end (cdr r) cf)
               (cons pos groups))))))

    (define (%run-range ranges ci)
      (let loop ((rs ranges))
        (cond
          ((null? rs) #f)
          ((and (>= ci (caar rs)) (<= ci (cdar rs))) #t)
          (else (loop (cdr rs))))))

    (define (%run-chars s c)
      (let loop ((i 0))
        (cond
          ((= i (string-length s)) #f)
          ((char=? c (string-ref s i)) #t)
          (else (loop (+ i 1))))))

    ;;; Main dispatcher — kept very small
    (define (%run compiled str pos end groups cf)
      (let ((tag (car compiled)))
        (cond
          ((eq? tag 'lit)
           (let ((p (%run-lit (cadr compiled) str pos end cf)))
             (if p (cons p groups) #f)))
          ((eq? tag 'chr)
           (if (and (< pos end) (%cm (string-ref str pos) (cadr compiled) cf))
               (cons (+ pos 1) groups) #f))
          ((eq? tag 'any) (if (< pos end) (cons (+ pos 1) groups) #f))
          ((eq? tag 'nonl)
           (if (and (< pos end) (not (char=? (string-ref str pos) #\newline))
                    (not (char=? (string-ref str pos) #\return)))
               (cons (+ pos 1) groups) #f))
          ((eq? tag 'class)
           (if (and (< pos end) (%match-class (string-ref str pos) (cadr compiled)))
               (cons (+ pos 1) groups) #f))
          ((eq? tag 'range)
           (if (and (< pos end) (%run-range (cadr compiled)
                     (char->integer (if cf (char-downcase (string-ref str pos)) (string-ref str pos)))))
               (cons (+ pos 1) groups) #f))
          ((eq? tag 'chars)
           (if (and (< pos end) (%run-chars (cadr compiled)
                     (if cf (char-downcase (string-ref str pos)) (string-ref str pos))))
               (cons (+ pos 1) groups) #f))
          (else (%run2 tag compiled str pos end groups cf)))))

    (define (%run2 tag compiled str pos end groups cf)
      (cond
        ((eq? tag 'assert)
         (if (%run-assert (cadr compiled) str pos end) (cons pos groups) #f))
        ((eq? tag 'seq) (%run-seq (cdr compiled) str pos end groups cf))
        ((eq? tag 'alt) (%run-alt (cdr compiled) str pos end groups cf))
        ((eq? tag 'opt)
         (let ((r (%run (cadr compiled) str pos end groups cf)))
           (if r r (cons pos groups))))
        ((eq? tag 'star) (%run-star (cadr compiled) str pos end groups cf))
        ((eq? tag 'plus) (%run-plus (cadr compiled) str pos end groups cf))
        (else (%run3 tag compiled str pos end groups cf))))

    (define (%run3 tag compiled str pos end groups cf)
      (cond
        ((eq? tag 'exactly) (%run-exactly (cadr compiled) (caddr compiled) str pos end groups cf))
        ((eq? tag 'at-least) (%run-at-least (cadr compiled) (caddr compiled) str pos end groups cf))
        ((eq? tag 'repeat) (%run-repeat 0 (cadr compiled) (caddr compiled) (cadddr compiled) str pos end groups cf))
        ((eq? tag 'group)
         (let ((r (%run (caddr compiled) str pos end groups cf)))
           (if r (cons (car r) (append (cdr r) (list (list (cadr compiled) pos (car r))))) #f)))
        ((eq? tag 'nocase) (%run (cadr compiled) str pos end groups #t))
        ((eq? tag 'case) (%run (cadr compiled) str pos end groups #f))
        ((eq? tag 'look) (if (%run (cadr compiled) str pos end groups cf) (cons pos groups) #f))
        ((eq? tag 'neglook) (if (%run (cadr compiled) str pos end groups cf) #f (cons pos groups)))
        ((eq? tag 'compl) (if (or (>= pos end) (%run (cadr compiled) str pos end groups cf)) #f
                              (cons (+ pos 1) groups)))
        (else (error "regexp: unknown tag" tag))))

    ;;; Public API

    (define (regexp re)
      (cond
        ((regexp? re) re)
        ((string? re) (regexp (list ': re)))
        (else (let ((gc (list 1))) (%make-regexp re (%csre re gc) (- (car gc) 1))))))

    (define-syntax rx (syntax-rules () ((rx sre ...) (regexp '(: sre ...)))))
    (define (regexp->sre re) (%regexp-sre (if (regexp? re) re (regexp re))))
    (define (valid-sre? obj) (guard (e (#t #f)) (regexp obj) #t))

    (define (%ensure re) (if (regexp? re) re (regexp re)))

    (define (%build-match str groups num-groups)
      (let ((vec (make-vector (+ num-groups 1) #f)))
        (for-each (lambda (g)
                    (if (< (car g) (vector-length vec))
                        (vector-set! vec (car g) (list (cadr g) (caddr g))))) groups)
        (%make-regexp-match str vec)))

    (define (regexp-matches? re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest)))
             (r (%ensure re))
             (m (%run (%regexp-compiled r) str start end '() #f)))
        (and m (= (car m) end))))

    (define (regexp-matches re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest)))
             (r (%ensure re))
             (m (%run (%regexp-compiled r) str start end '() #f)))
        (if (and m (= (car m) end))
            (%build-match str (cons (list 0 start end) (cdr m)) (%regexp-num-groups r))
            #f)))

    (define (regexp-search re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest)))
             (r (%ensure re)))
        (let loop ((i start))
          (if (> i end) #f
              (let ((m (%run (%regexp-compiled r) str i end '() #f)))
                (if m (%build-match str (cons (list 0 i (car m)) (cdr m)) (%regexp-num-groups r))
                    (loop (+ i 1))))))))

    (define (regexp-match-count m) (- (vector-length (%match-groups m)) 1))
    (define (regexp-match-submatch m field)
      (let ((g (vector-ref (%match-groups m) field)))
        (if g (substring (%match-str m) (car g) (cadr g)) #f)))
    (define (regexp-match-submatch-start m field)
      (let ((g (vector-ref (%match-groups m) field))) (if g (car g) #f)))
    (define (regexp-match-submatch-end m field)
      (let ((g (vector-ref (%match-groups m) field))) (if g (cadr g) #f)))
    (define (regexp-match->list m)
      (let loop ((i 0) (r '()))
        (if (> i (regexp-match-count m)) (reverse r)
            (loop (+ i 1) (cons (regexp-match-submatch m i) r)))))

    (define (regexp-fold re kons knil str . rest)
      (let* ((finish (if (null? rest) (lambda (i m s acc) acc) (car rest)))
             (rest2 (if (null? rest) '() (cdr rest)))
             (start (if (null? rest2) 0 (car rest2)))
             (rest3 (if (null? rest2) '() (cdr rest2)))
             (end (if (null? rest3) (string-length str) (car rest3)))
             (r (%ensure re)))
        (let loop ((i start) (acc knil))
          (if (> i end) (finish i #f str acc)
              (let ((m-obj (regexp-search r str i end)))
                (if (not m-obj) (finish i #f str acc)
                    (let ((ms (regexp-match-submatch-start m-obj 0))
                          (me (regexp-match-submatch-end m-obj 0)))
                      (let ((acc2 (kons i m-obj str acc)))
                        (if (= me ms)
                            (if (>= me end) (finish me m-obj str acc2) (loop (+ me 1) acc2))
                            (loop me acc2))))))))))

    (define (regexp-extract re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest))))
        (reverse
          (regexp-fold re
            (lambda (i m s acc)
              (let ((sub (regexp-match-submatch m 0)))
                (if (and sub (> (string-length sub) 0)) (cons sub acc) acc)))
            '() str (lambda (i m s acc) acc) start end))))

    (define (regexp-split re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest))))
        (reverse
          (regexp-fold re
            (lambda (i m s acc) (cons (substring s i (regexp-match-submatch-start m 0)) acc))
            '() str (lambda (i m s acc) (cons (substring s i end) acc)) start end))))

    (define (regexp-partition re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest))))
        (reverse
          (regexp-fold re
            (lambda (i m s acc)
              (cons (regexp-match-submatch m 0)
                    (cons (substring s i (regexp-match-submatch-start m 0)) acc)))
            '() str (lambda (i m s acc) (cons (substring s i end) acc)) start end))))

    (define (%apply-subst subst m-obj str)
      (cond
        ((string? subst) subst)
        ((integer? subst) (or (regexp-match-submatch m-obj subst) ""))
        ((eq? subst 'pre) (substring str 0 (regexp-match-submatch-start m-obj 0)))
        ((eq? subst 'post) (substring str (regexp-match-submatch-end m-obj 0) (string-length str)))
        ((procedure? subst) (subst m-obj))
        (else (error "regexp-replace: invalid substitution" subst))))

    (define (regexp-replace re str subst . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (rest2 (if (null? rest) '() (cdr rest)))
             (end (if (null? rest2) (string-length str) (car rest2)))
             (rest3 (if (null? rest2) '() (cdr rest2)))
             (count (if (null? rest3) 0 (car rest3)))
             (r (%ensure re)))
        (let loop ((i start) (n 0))
          (if (> i end) str
              (let ((m-obj (regexp-search r str i end)))
                (if (not m-obj) str
                    (if (= n count)
                        (let ((ms (regexp-match-submatch-start m-obj 0))
                              (me (regexp-match-submatch-end m-obj 0)))
                          (string-append (substring str 0 ms) (%apply-subst subst m-obj str)
                                         (substring str me (string-length str))))
                        (let ((me (regexp-match-submatch-end m-obj 0)))
                          (loop (if (= me i) (+ me 1) me) (+ n 1))))))))))

    (define (regexp-replace-all re str subst . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest)))
             (r (%ensure re)))
        (apply string-append
          (reverse
            (regexp-fold r
              (lambda (i m s acc)
                (cons (%apply-subst subst m s)
                      (cons (substring s i (regexp-match-submatch-start m 0)) acc)))
              '() str (lambda (i m s acc) (cons (substring s i end) acc)) start end)))))

    ))
