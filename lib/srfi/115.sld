(define-library (srfi 115)
  (import (scheme base) (scheme char) (scheme case-lambda) (scheme cxr))
  (export regexp rx regexp? regexp-matches? regexp-matches regexp-search
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

    ;; Every named char class %match-class understands. An unknown symbol
    ;; must be a compile-time error, not a silent match-nothing (a typo
    ;; like 'digit for 'numeric would otherwise just make every search
    ;; return #f).
    (define %class-names
      '(alphabetic alpha numeric num lower-case lower upper-case upper
        whitespace white space alphanumeric alphanum alnum
        punctuation punct word hex-digit xdigit ascii
        control cntrl graphic graph printing print))

    (define (%csre sre gc)
      (cond
        ((string? sre) (list 'lit sre))
        ((char? sre) (list 'chr sre))
        ((and (symbol? sre) (memq sre '(bos eos bol eol bow eow nwb))) (list 'assert sre))
        ((eq? sre 'any) (list 'any))
        ((eq? sre 'nonl) (list 'nonl))
        ((symbol? sre)
         (if (memq sre %class-names)
             (list 'class sre)
             (error "regexp: unknown character class" sre)))
        ((not (pair? sre)) (error "regexp: invalid SRE" sre))
        (else
         (let ((h (car sre)))
           (cond
             ;; A list whose head is a string is a char set spelled out by its
             ;; characters, e.g. (",;") -- SRFI 115's <cset-sre> shorthand.
             ((string? h) (list 'chars h))
             ((or (eq? h 'seq) (eq? h ':))
              (cons 'seq (map (lambda (s) (%csre s gc)) (cdr sre))))
             ((eq? h 'or)
              (cons 'alt (map (lambda (s) (%csre s gc)) (cdr sre))))
             ((or (eq? h '?) (eq? h 'optional))
              (list 'opt (%cbody (cdr sre) gc) #t))
             ((or (eq? h '??) (eq? h 'non-greedy-optional))
              (list 'opt (%cbody (cdr sre) gc) #f))
             ((or (eq? h '*) (eq? h 'zero-or-more))
              (list 'rep 0 #f (%cbody (cdr sre) gc) #t))
             ((or (eq? h '*?) (eq? h 'non-greedy-zero-or-more))
              (list 'rep 0 #f (%cbody (cdr sre) gc) #f))
             ((or (eq? h '+) (eq? h 'one-or-more))
              (list 'rep 1 #f (%cbody (cdr sre) gc) #t))
             ((or (eq? h '=) (eq? h 'exactly))
              (list 'rep (cadr sre) (cadr sre) (%cbody (cddr sre) gc) #t))
             ((or (eq? h '>=) (eq? h 'at-least))
              (list 'rep (cadr sre) #f (%cbody (cddr sre) gc) #t))
             ((or (eq? h '**) (eq? h 'repeated))
              (list 'rep (cadr sre) (caddr sre) (%cbody (cdddr sre) gc) #t))
             ((or (eq? h '**?) (eq? h 'non-greedy-repeated))
              (list 'rep (cadr sre) (caddr sre) (%cbody (cdddr sre) gc) #f))
             ((or (eq? h '$) (eq? h 'submatch))
              (let ((gn (car gc))) (set-car! gc (+ gn 1))
                (list 'group gn (%cbody (cdr sre) gc))))
             ((or (eq? h %sym-arrow) (eq? h 'submatch-named))
              (let ((gn (car gc))) (set-car! gc (+ gn 1))
                (list 'group gn (%cbody (cddr sre) gc))))
             ((eq? h 'w/nocase) (list 'nocase (%cbody (cdr sre) gc)))
             ((eq? h 'w/case) (list 'case (%cbody (cdr sre) gc)))
             ((or (eq? h '/) (eq? h 'char-range))
              (list 'range (%build-ranges (cdr sre))))
             ((eq? h 'char-set) (list 'chars (cadr sre)))
             ((or (eq? h '~) (eq? h 'complement))
              (list 'compl (%cbody (cdr sre) gc)))
             ((eq? h 'look-ahead) (list 'look (%cbody (cdr sre) gc)))
             ((eq? h 'neg-look-ahead) (list 'neglook (%cbody (cdr sre) gc)))
             ((eq? h 'word)
              (list 'seq (list 'assert 'bow) (%cbody (cdr sre) gc) (list 'assert 'eow)))
             ((or (eq? h 'w/nocapture) (eq? h 'w/ascii) (eq? h 'w/unicode))
              (%cbody (cdr sre) gc))
             (else (error "regexp: unknown SRE" h)))))))

    (define (%cbody sres gc)
      (if (null? (cdr sres)) (%csre (car sres) gc)
          (cons 'seq (map (lambda (s) (%csre s gc)) sres))))

    ;; (/ <range-spec> ...) takes strings and/or characters; the flattened
    ;; character sequence is read off in pairs, so (/ "az" #\0 #\9) is the same
    ;; set as (/ "az09"). Characters used to be dropped silently, which turned
    ;; the SSRE-generated (char-range #\0 #\9) into a set matching nothing.
    (define (%build-ranges specs)
      (let ((chars
             (let loop ((specs specs) (acc '()))
               (if (null? specs) (reverse acc)
                   (let ((spec (car specs)))
                     (cond
                       ((char? spec) (loop (cdr specs) (cons spec acc)))
                       ((string? spec)
                        (loop (cdr specs)
                              (let sloop ((i 0) (acc acc))
                                (if (>= i (string-length spec)) acc
                                    (sloop (+ i 1) (cons (string-ref spec i) acc))))))
                       (else (error "regexp: invalid character range" spec))))))))
        (let loop ((cs chars) (ranges '()))
          (if (or (null? cs) (null? (cdr cs))) ranges
              (loop (cddr cs)
                    (cons (cons (char->integer (car cs))
                                (char->integer (cadr cs))) ranges))))))

    ;;; Match interpreter

    ;; Under case folding (w/nocase) a class stands for its case-closure, so
    ;; `lower' also accepts #\D: it is the set of characters whose downcased
    ;; form is lowercase, not the set of lowercase characters.
    (define (%match-class c name cf)
      (cond
        ((or (eq? name 'alphabetic) (eq? name 'alpha)) (char-alphabetic? c))
        ((or (eq? name 'numeric) (eq? name 'num)) (char-numeric? c))
        ((or (eq? name 'lower-case) (eq? name 'lower))
         (char-lower-case? (if cf (char-downcase c) c)))
        ((or (eq? name 'upper-case) (eq? name 'upper))
         (char-upper-case? (if cf (char-upcase c) c)))
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
        ;; nwb holds wherever bow/eow do not: both neighbours are word
        ;; characters, or neither is (the ends of the range count as non-word).
        ((eq? kind 'nwb)
         (eq? (and (> pos 0) (%char-word? (string-ref str (- pos 1))) #t)
              (and (< pos end) (%char-word? (string-ref str pos)) #t)))
        (else #f)))

    ;; The matcher is continuation-passing so that repetition can backtrack:
    ;; %run offers each way its node can match to (k pos groups), in preference
    ;; order, and yields the first non-#f answer k returns. A greedy operator
    ;; offers the longest alternative first, a non-greedy one the shortest.
    ;; Without this, `(regexp-matches (rx (* any) "b") "ab")' failed -- (* any)
    ;; swallowed the whole string and nothing could hand a character back.
    (define (%run-done pos groups) (cons pos groups))

    ;; Does `node' match a single character at `pos'? Used both by %run and by
    ;; the iterative repetition path below.
    (define (%match-one node str pos end cf)
      (and (< pos end)
           (let ((tag (car node)) (c (string-ref str pos)))
             (cond
               ((eq? tag 'chr) (%cm c (cadr node) cf))
               ((eq? tag 'any) #t)
               ((eq? tag 'nonl) (and (not (char=? c #\newline)) (not (char=? c #\return))))
               ((eq? tag 'class) (%match-class c (cadr node) cf))
               ((eq? tag 'range) (%match-range c (cadr node) cf))
               ((eq? tag 'chars) (%match-chars c (cadr node) cf))
               ((eq? tag 'nocase) (%match-one (cadr node) str pos end #t))
               ((eq? tag 'case) (%match-one (cadr node) str pos end #f))
               ((eq? tag 'alt)
                (let loop ((ps (cdr node)))
                  (and (pair? ps)
                       (or (%match-one (car ps) str pos end cf) (loop (cdr ps))))))
               ((eq? tag 'compl)
                (not (%run (cadr node) str pos end '() cf %run-done)))
               (else #f)))))

    ;; A node that always consumes exactly one character and captures nothing
    ;; can be repeated by scanning, so `(* any)' over a long string costs no
    ;; stack -- only the general path below nests one frame per iteration.
    (define (%single-char-node? node)
      (let ((tag (car node)))
        (cond
          ((memq tag '(chr any nonl class range chars compl)) #t)
          ((memq tag '(nocase case)) (%single-char-node? (cadr node)))
          ((eq? tag 'alt) (%every %single-char-node? (cdr node)))
          (else #f))))

    (define (%every pred ls)
      (or (null? ls) (and (pred (car ls)) (%every pred (cdr ls)))))

    (define (%match-range c ranges cf)
      (let ((try (lambda (ch)
                   (let ((ci (char->integer ch)))
                     (let loop ((rs ranges))
                       (cond
                         ((null? rs) #f)
                         ((and (>= ci (caar rs)) (<= ci (cdar rs))) #t)
                         (else (loop (cdr rs)))))))))
        (or (try c) (and cf (or (try (char-downcase c)) (try (char-upcase c)))))))

    (define (%match-chars c s cf)
      (let loop ((i 0))
        (cond
          ((= i (string-length s)) #f)
          ((%cm c (string-ref s i) cf) #t)
          (else (loop (+ i 1))))))

    (define (%run-seq parts str pos end groups cf k)
      (if (null? parts) (k pos groups)
          (%run (car parts) str pos end groups cf
                (lambda (p g) (%run-seq (cdr parts) str p end g cf k)))))

    (define (%run-alt parts str pos end groups cf k)
      (if (null? parts) #f
          (or (%run (car parts) str pos end groups cf k)
              (%run-alt (cdr parts) str pos end groups cf k))))

    ;; (rep lo hi body greedy?); hi of #f means unbounded. The (> p pos)
    ;; guard on optional iterations keeps a nullable body from looping.
    (define (%run-rep lo hi inner str pos end groups cf greedy k)
      (if (%single-char-node? inner)
          (%run-rep1 lo hi inner str pos end groups cf greedy k)
          (cond
            ((> lo 0)
             (%run inner str pos end groups cf
                   (lambda (p g)
                     (%run-rep (- lo 1) (and hi (- hi 1)) inner
                               str p end g cf greedy k))))
            ((and hi (<= hi 0)) (k pos groups))
            (else
             (let ((more (lambda ()
                           (%run inner str pos end groups cf
                                 (lambda (p g)
                                   (and (> p pos)
                                        (%run-rep 0 (and hi (- hi 1)) inner
                                                  str p end g cf greedy k)))))))
               (if greedy (or (more) (k pos groups)) (or (k pos groups) (more))))))))

    ;; Repetition of a single-character body: count the longest run available,
    ;; then offer lengths to k from the preferred end.
    (define (%run-rep1 lo hi inner str pos end groups cf greedy k)
      (let* ((limit (if hi (min end (+ pos hi)) end))
             (most (let loop ((p pos))
                     (if (and (< p limit) (%match-one inner str p end cf))
                         (loop (+ p 1))
                         (- p pos)))))
        (and (>= most lo)
             (if greedy
                 (let loop ((n most))
                   (and (>= n lo) (or (k (+ pos n) groups) (loop (- n 1)))))
                 (let loop ((n lo))
                   (and (<= n most) (or (k (+ pos n) groups) (loop (+ n 1)))))))))

    (define (%run compiled str pos end groups cf k)
      (let ((tag (car compiled)))
        (cond
          ((eq? tag 'lit)
           (let* ((s (cadr compiled)) (slen (string-length s)))
             (and (<= (+ pos slen) end)
                  (let loop ((i 0))
                    (if (= i slen) (k (+ pos slen) groups)
                        (and (%cm (string-ref str (+ pos i)) (string-ref s i) cf)
                             (loop (+ i 1))))))))
          ((memq tag '(chr any nonl class range chars))
           (and (%match-one compiled str pos end cf) (k (+ pos 1) groups)))
          ((eq? tag 'assert)
           (and (%run-assert (cadr compiled) str pos end) (k pos groups)))
          ((eq? tag 'seq) (%run-seq (cdr compiled) str pos end groups cf k))
          ((eq? tag 'alt) (%run-alt (cdr compiled) str pos end groups cf k))
          ((eq? tag 'opt)
           (if (caddr compiled)
               (or (%run (cadr compiled) str pos end groups cf k) (k pos groups))
               (or (k pos groups) (%run (cadr compiled) str pos end groups cf k))))
          ((eq? tag 'rep)
           (%run-rep (cadr compiled) (caddr compiled) (cadddr compiled)
                     str pos end groups cf (car (cddddr compiled)) k))
          ((eq? tag 'group)
           (let ((gn (cadr compiled)))
             (%run (caddr compiled) str pos end groups cf
                   (lambda (p g) (k p (append g (list (list gn pos p))))))))
          ((eq? tag 'nocase) (%run (cadr compiled) str pos end groups #t k))
          ((eq? tag 'case) (%run (cadr compiled) str pos end groups #f k))
          ((eq? tag 'look)
           (and (%run (cadr compiled) str pos end groups cf %run-done) (k pos groups)))
          ((eq? tag 'neglook)
           (and (not (%run (cadr compiled) str pos end groups cf %run-done)) (k pos groups)))
          ((eq? tag 'compl)
           (and (%match-one compiled str pos end cf) (k (+ pos 1) groups)))
          (else (error "regexp: unknown tag" tag)))))

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

    ;; Anchoring the whole string is part of the continuation, not a test on
    ;; the result: a pattern that can match a prefix must be free to backtrack
    ;; until it reaches `end' before regexp-matches gives up.
    (define (%run-anchored r str start end)
      (%run (%regexp-compiled r) str start end '() #f
            (lambda (p g) (and (= p end) (cons p g)))))

    (define (regexp-matches? re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest))))
        (and (%run-anchored (%ensure re) str start end) #t)))

    (define (regexp-matches re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest)))
             (r (%ensure re))
             (m (%run-anchored r str start end)))
        (if m
            (%build-match str (cons (list 0 start end) (cdr m)) (%regexp-num-groups r))
            #f)))

    (define (regexp-search re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest)))
             (r (%ensure re)))
        (let loop ((i start))
          (if (> i end) #f
              (let ((m (%run (%regexp-compiled r) str i end '() #f %run-done)))
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

    ;; The index handed to kons/finish is where the *previous* match ended, not
    ;; where this search started: after an empty match the search cursor skips a
    ;; character, but the unmatched text still begins back at the previous end.
    ;; Conflating the two made regexp-split/-partition return a run of empty
    ;; strings for any regexp that can match the empty string.
    (define (regexp-fold re kons knil str . rest)
      (let* ((finish (if (null? rest) (lambda (i m s acc) acc) (car rest)))
             (rest2 (if (null? rest) '() (cdr rest)))
             (start (if (null? rest2) 0 (car rest2)))
             (rest3 (if (null? rest2) '() (cdr rest2)))
             (end (if (null? rest3) (string-length str) (car rest3)))
             (r (%ensure re)))
        (let loop ((i start) (from start) (acc knil))
          (let ((m-obj (and (< i end) (regexp-search r str i end))))
            (if (not m-obj) (finish from #f str acc)
                (let ((ms (regexp-match-submatch-start m-obj 0))
                      (me (regexp-match-submatch-end m-obj 0)))
                  (loop (if (and (= me ms) (< me end)) (+ me 1) me)
                        me
                        (kons from m-obj str acc))))))))

    (define (regexp-extract re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest))))
        (regexp-fold re
          (lambda (i m s acc)
            (let ((sub (regexp-match-submatch m 0)))
              (if (and sub (> (string-length sub) 0)) (cons sub acc) acc)))
          '() str (lambda (i m s acc) (reverse acc)) start end)))

    ;; split/partition carry the left edge of the pending piece in (car acc) and
    ;; ignore empty matches, so a nullable regexp splits on its real matches.
    (define (regexp-split re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest))))
        (regexp-fold re
          (lambda (i m s acc)
            (let ((ms (regexp-match-submatch-start m 0))
                  (me (regexp-match-submatch-end m 0)))
              (if (= ms me) acc
                  (cons me (cons (substring s (car acc) ms) (cdr acc))))))
          (list start) str
          (lambda (i m s acc) (reverse (cons (substring s (car acc) end) (cdr acc))))
          start end)))

    (define (regexp-partition re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest))))
        (regexp-fold re
          (lambda (i m s acc)
            (let ((ms (regexp-match-submatch-start m 0))
                  (me (regexp-match-submatch-end m 0)))
              (if (= ms me) acc
                  (cons me (cons (regexp-match-submatch m 0)
                                 (cons (substring s (car acc) ms) (cdr acc)))))))
          (list start) str
          (lambda (i m s acc)
            (reverse (if (or (< i end) (null? (cdr acc)))
                         (cons (substring s (car acc) end) (cdr acc))
                         (cdr acc))))
          start end)))

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
