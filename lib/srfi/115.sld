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
      (%make-regexp sre compiled num-groups names)
      regexp?
      (sre %regexp-sre)
      (compiled %regexp-compiled)
      (num-groups %regexp-num-groups)
      ;; ((<name> . <group number>) ...) for (-> name sre ...), in group
      ;; order.  A name may repeat: submatch lookup takes the first that
      ;; actually matched.
      (names %regexp-names))

    (define-record-type <regexp-match>
      (%make-regexp-match str groups names)
      regexp-match?
      (str %match-str)
      (groups %match-groups)
      (names %match-names))

    (define %sym-arrow (string->symbol "->"))
    (define (%char-word? c) (or (char-alphabetic? c) (char-numeric? c) (char=? c #\_)))
    (define (%cm a b cf) (if cf (char=? (char-downcase a) (char-downcase b)) (char=? a b)))

    ;;; Compile SRE to data structure

    ;; Every named char class %match-class understands. An unknown symbol
    ;; must be a compile-time error, not a silent match-nothing (a typo
    ;; like 'digit for 'numeric would otherwise just make every search
    ;; return #f).  `word' is deliberately absent: SRFI 115 spells the bare
    ;; symbol as a whole word, not as one word-constituent character.
    (define %class-names
      '(alphabetic alpha numeric num lower-case lower upper-case upper
        title-case title symbol whitespace white space
        alphanumeric alphanum alnum
        punctuation punct hex-digit xdigit ascii
        control cntrl graphic graph printing print))

    ;; Compilation carries a mutable context: the next submatch number, the
    ;; names collected for (-> name ...) so far, whether we are inside
    ;; w/ascii, and whether we are inside w/nocapture.  It is a box rather
    ;; than four more arguments because every %csre arm would otherwise have
    ;; to thread them.
    (define %ctx/ascii 2)
    (define %ctx/nocapture 3)
    (define (%make-ctx) (vector 1 '() #f #f))
    (define (%ctx-groups ctx) (vector-ref ctx 0))
    (define (%ctx-names ctx) (reverse (vector-ref ctx 1)))
    (define (%ctx-ascii? ctx) (vector-ref ctx %ctx/ascii))
    (define (%ctx-nocapture? ctx) (vector-ref ctx %ctx/nocapture))

    ;; Allocate a submatch number, or #f under w/nocapture.
    (define (%ctx-next-group! ctx name)
      (and (not (%ctx-nocapture? ctx))
           (let ((gn (vector-ref ctx 0)))
             (vector-set! ctx 0 (+ gn 1))
             (if name
                 (vector-set! ctx 1 (cons (cons name gn) (vector-ref ctx 1))))
             gn)))

    ;; Compile `sres' with slot `i' of the context bound to `val', restoring
    ;; it afterwards -- w/ascii, w/unicode and w/nocapture are all lexical.
    (define (%cbody-with ctx i val sres)
      (let ((saved (vector-ref ctx i)))
        (vector-set! ctx i val)
        (let ((node (%cbody sres ctx)))
          (vector-set! ctx i saved)
          node)))

    (define (%csre sre ctx)
      (cond
        ((string? sre) (list 'lit sre))
        ((char? sre) (list 'chr sre))
        ((and (symbol? sre) (memq sre '(bos eos bol eol bow eow nwb)))
         (list 'assert sre))
        ;; bog/eog always hold in an ASCII context, and grapheme degrades to
        ;; any -- an ASCII character is a cluster by itself.
        ((memq sre '(bog eog))
         (if (%ctx-ascii? ctx) (list 'seq) (list 'assert sre)))
        ((eq? sre 'grapheme)
         (if (%ctx-ascii? ctx) (list 'any #t) (list 'grapheme)))
        ((eq? sre 'any) (list 'any (%ctx-ascii? ctx)))
        ((eq? sre 'nonl) (list 'nonl (%ctx-ascii? ctx)))
        ;; (word+ any) intersected with the word constituents is just the
        ;; word constituents, so bare `word' passes no cset at all.
        ((eq? sre 'word) (%cword '() ctx))
        ((symbol? sre)
         (if (memq sre %class-names)
             (list 'class sre (%ctx-ascii? ctx))
             (error "regexp: unknown character class" sre)))
        ((not (pair? sre)) (error "regexp: invalid SRE" sre))
        (else
         (let ((h (car sre)))
           (cond
             ;; A list whose head is a string is a char set spelled out by its
             ;; characters, e.g. (",;") -- SRFI 115's <cset-sre> shorthand.
             ((string? h) (list 'chars h))
             ((or (eq? h 'seq) (eq? h ':))
              (cons 'seq (map (lambda (s) (%csre s ctx)) (cdr sre))))
             ((eq? h 'or)
              (cons 'alt (map (lambda (s) (%csre s ctx)) (cdr sre))))
             ((or (eq? h '?) (eq? h 'optional))
              (list 'opt (%cbody (cdr sre) ctx) #t))
             ((or (eq? h '??) (eq? h 'non-greedy-optional))
              (list 'opt (%cbody (cdr sre) ctx) #f))
             ((or (eq? h '*) (eq? h 'zero-or-more))
              (list 'rep 0 #f (%cbody (cdr sre) ctx) #t))
             ((or (eq? h '*?) (eq? h 'non-greedy-zero-or-more))
              (list 'rep 0 #f (%cbody (cdr sre) ctx) #f))
             ((or (eq? h '+) (eq? h 'one-or-more))
              (list 'rep 1 #f (%cbody (cdr sre) ctx) #t))
             ((or (eq? h '=) (eq? h 'exactly))
              (list 'rep (cadr sre) (cadr sre) (%cbody (cddr sre) ctx) #t))
             ((or (eq? h '>=) (eq? h 'at-least))
              (list 'rep (cadr sre) #f (%cbody (cddr sre) ctx) #t))
             ((or (eq? h '**) (eq? h 'repeated))
              (list 'rep (cadr sre) (caddr sre) (%cbody (cdddr sre) ctx) #t))
             ((or (eq? h '**?) (eq? h 'non-greedy-repeated))
              (list 'rep (cadr sre) (caddr sre) (%cbody (cdddr sre) ctx) #f))
             ((or (eq? h '$) (eq? h 'submatch))
              (%cgroup (%ctx-next-group! ctx #f) (cdr sre) ctx))
             ((or (eq? h %sym-arrow) (eq? h 'submatch-named))
              (%cgroup (%ctx-next-group! ctx (cadr sre)) (cddr sre) ctx))
             ((eq? h 'w/nocase) (list 'nocase (%cbody (cdr sre) ctx)))
             ((eq? h 'w/case) (list 'case (%cbody (cdr sre) ctx)))
             ((or (eq? h '/) (eq? h 'char-range))
              (list 'range (%build-ranges (cdr sre))))
             ((eq? h 'char-set) (list 'chars (cadr sre)))
             ;; The cset operators all take <cset-sre>s, i.e. one-character
             ;; nodes.  (~ a b) is the complement of the *union*, not of the
             ;; sequence, so it folds its arguments with %cunion.
             ((or (eq? h '~) (eq? h 'complement))
              (list 'compl (%cunion (cdr sre) ctx) (%ctx-ascii? ctx)))
             ((or (eq? h '&) (eq? h 'and))
              (if (null? (cdr sre))
                  (list 'any (%ctx-ascii? ctx))
                  (cons 'cand (map (lambda (s) (%csre s ctx)) (cdr sre)))))
             ((or (eq? h '-) (eq? h 'difference))
              (list 'cdiff (%csre (cadr sre) ctx) (%cunion (cddr sre) ctx)))
             ((eq? h 'look-ahead) (list 'look (%cbody (cdr sre) ctx)))
             ((eq? h 'neg-look-ahead) (list 'neglook (%cbody (cdr sre) ctx)))
             ((eq? h 'look-behind) (list 'lookb (%cbody (cdr sre) ctx)))
             ((eq? h 'neg-look-behind) (list 'neglookb (%cbody (cdr sre) ctx)))
             ((eq? h 'word)
              (list 'seq (list 'assert 'bow) (%cbody (cdr sre) ctx)
                    (list 'assert 'eow)))
             ((eq? h 'word+) (%cword (cdr sre) ctx))
             ((eq? h 'w/nocapture) (%cbody-with ctx %ctx/nocapture #t (cdr sre)))
             ((eq? h 'w/ascii) (%cbody-with ctx %ctx/ascii #t (cdr sre)))
             ((eq? h 'w/unicode) (%cbody-with ctx %ctx/ascii #f (cdr sre)))
             (else (error "regexp: unknown SRE" h)))))))

    (define (%cbody sres ctx)
      (if (null? (cdr sres)) (%csre (car sres) ctx)
          (cons 'seq (map (lambda (s) (%csre s ctx)) sres))))

    ;; Char set union of a <cset-sre> list; an empty union matches nothing.
    (define (%cunion sres ctx)
      (cons 'alt (map (lambda (s) (%csre s ctx)) sres)))

    ;; (w/nocapture ($ x)) still has to match x -- it just does not capture,
    ;; and does not consume a submatch number.
    (define (%cgroup gn sres ctx)
      (let ((body (%cbody sres ctx)))
        (if gn (list 'group gn body) body)))

    ;; (word+ cset ...) is (word (+ (and (or alphanumeric "_") (or cset ...)))),
    ;; and the bare symbol `word' is (word+ any).
    (define (%cword csets ctx)
      (let* ((wc (list 'class 'word-constituent (%ctx-ascii? ctx)))
             (body (if (null? csets)
                       wc
                       (list 'cand wc (%cunion csets ctx)))))
        (list 'seq (list 'assert 'bow) (list 'rep 1 #f body #t)
              (list 'assert 'eow))))

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
    ;;
    ;; `ascii?' is the w/ascii context.  Every named set with both an ASCII
    ;; and a Unicode definition is the Unicode one restricted to [0..127],
    ;; so one guard covers them all -- (w/ascii alpha) is (/ "azAZ"), and
    ;; (w/ascii title) is empty because no ASCII character is titlecase.
    (define (%match-class c name cf ascii?)
      (and (or (not ascii?) (< (char->integer c) 128))
           (%match-class* c name cf)))

    (define (%match-class* c name cf)
      (cond
        ((or (eq? name 'alphabetic) (eq? name 'alpha)) (char-alphabetic? c))
        ((or (eq? name 'numeric) (eq? name 'num)) (char-numeric? c))
        ((or (eq? name 'lower-case) (eq? name 'lower))
         (char-lower-case? (if cf (char-downcase c) c)))
        ((or (eq? name 'upper-case) (eq? name 'upper))
         (char-upper-case? (if cf (char-upcase c) c)))
        ;; Under w/nocase a titlecase ligature is reachable from its lower-
        ;; and uppercase forms, matching how `lower' and `upper' widen.
        ((or (eq? name 'title-case) (eq? name 'title))
         (or (%in-table? %cs-title-case (char->integer c))
             (and cf (or (%in-table? %cs-title-case (char->integer (char-upcase c)))
                         (%in-table? %cs-title-case (char->integer (char-downcase c)))))))
        ((eq? name 'symbol) (%in-table? %cs-symbol (char->integer c)))
        ((or (eq? name 'whitespace) (eq? name 'white) (eq? name 'space)) (char-whitespace? c))
        ((or (eq? name 'alphanumeric) (eq? name 'alphanum) (eq? name 'alnum))
         (or (char-alphabetic? c) (char-numeric? c)))
        ((or (eq? name 'punctuation) (eq? name 'punct))
         (and (not (char-alphabetic? c)) (not (char-numeric? c))
              (not (char-whitespace? c)) (>= (char->integer c) 33) (<= (char->integer c) 126)))
        ;; Not an SRFI 115 name -- what (word+ ...) intersects with.
        ((eq? name 'word-constituent) (%char-word? c))
        ((or (eq? name 'hex-digit) (eq? name 'xdigit))
         (or (char-numeric? c) (and (char>=? (char-downcase c) #\a) (char<=? (char-downcase c) #\f))))
        ((eq? name 'ascii) (<= (char->integer c) 127))
        ((or (eq? name 'control) (eq? name 'cntrl)) (< (char->integer c) 32))
        ((or (eq? name 'graphic) (eq? name 'graph))
         (and (not (char-whitespace? c)) (>= (char->integer c) 33)))
        ((or (eq? name 'printing) (eq? name 'print)) (>= (char->integer c) 32))
        (else #f)))

    ;;; Extended grapheme clusters (UAX #29)

    ;; Grapheme cluster break class of a codepoint.  Extend, SpacingMark and
    ;; ZWJ all join to the left, so they share the single class `mark'.
    ;; Hangul syllables are arithmetic: the block is laid out L*21*28 + V*28 + T.
    (define (%gcb cp)
      (cond
        ((= cp 13) 'cr)
        ((= cp 10) 'lf)
        ((%in-table? %cs-mark cp) 'mark)
        ((%in-table? %cs-gcb-control cp) 'control)
        ((%in-table? %cs-prepend cp) 'prepend)
        ((and (>= cp #x1F1E6) (<= cp #x1F1FF)) 'ri)
        ((or (and (>= cp #x1100) (<= cp #x115F))
             (and (>= cp #xA960) (<= cp #xA97C))) 'l)
        ((or (and (>= cp #x1160) (<= cp #x11A7))
             (and (>= cp #xD7B0) (<= cp #xD7C6))) 'v)
        ((or (and (>= cp #x11A8) (<= cp #x11FF))
             (and (>= cp #xD7CB) (<= cp #xD7FB))) 't)
        ((and (>= cp #xAC00) (<= cp #xD7A3))
         (if (= 0 (remainder (- cp #xAC00) 28)) 'lv 'lvt))
        (else 'other)))

    ;; Do classes `a' and `b' stay in the same cluster?  `ri' is how many
    ;; regional indicators run up to and including `a', so that flag pairs
    ;; join but a third indicator starts a new cluster (UAX #29 GB12/GB13).
    (define (%gcb-join? a b ri)
      (cond
        ((eq? a 'cr) (eq? b 'lf))                       ; GB3
        ((memq a '(lf control)) #f)                     ; GB4
        ((memq b '(cr lf control)) #f)                  ; GB5
        ((eq? b 'mark) #t)                              ; GB9, GB9a
        ((eq? a 'prepend) #t)                           ; GB9b
        ((eq? a 'l) (and (memq b '(l v lv lvt)) #t))    ; GB6
        ((memq a '(lv v)) (and (memq b '(v t)) #t))     ; GB7
        ((memq a '(lvt t)) (eq? b 't))                  ; GB8
        ((eq? a 'ri) (and (eq? b 'ri) (odd? ri)))       ; GB12, GB13
        (else #f)))                                     ; GB999

    ;; Index just past the grapheme cluster starting at `pos'.  Always
    ;; advances when pos < end, so callers can iterate on it.
    (define (%grapheme-end str pos end)
      (let loop ((i pos) (prev #f) (ri 0))
        (if (>= i end)
            i
            (let ((this (%gcb (char->integer (string-ref str i)))))
              (if (or (not prev) (%gcb-join? prev this ri))
                  (loop (+ i 1) this (if (eq? this 'ri) (+ ri 1) 0))
                  i)))))

    ;; Is `pos' on a cluster boundary?  Clusters are counted from `start',
    ;; which SRFI 115 says to treat as preceded by a non-combining codepoint.
    (define (%grapheme-boundary? str start pos end)
      (let loop ((i start))
        (cond
          ((>= i pos) (= i pos))
          ((>= i end) #f)
          (else (loop (%grapheme-end str i end))))))

    (define (%run-assert kind str start pos end)
      (cond
        ((eq? kind 'bos) (= pos 0))
        ((eq? kind 'eos) (= pos end))
        ((eq? kind 'bog)
         (and (< pos end) (%grapheme-boundary? str start pos end)))
        ((eq? kind 'eog)
         (and (> pos start) (%grapheme-boundary? str start pos end)))
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
    ;;
    ;; This buys correctness at the usual price: quantifiers nested over the
    ;; same span, as in `(: (* (* #\a)) #\b)', backtrack exponentially, since
    ;; the outer repetition has exponentially many ways to partition what the
    ;; inner one matched. See the SRFI 115 note in CONFORMANCE.md.
    (define (%run-done pos groups) (cons pos groups))

    ;; Does `node' match a single character at `pos'? Used both by %run and by
    ;; the iterative repetition path below.  Every <cset-sre> compiles to a
    ;; node this understands, so the set operators (~, &, -) are decided here
    ;; without re-entering the backtracking matcher.
    (define (%match-one node str pos end cf)
      (and (< pos end)
           (let ((tag (car node)) (c (string-ref str pos)))
             (cond
               ((eq? tag 'chr) (%cm c (cadr node) cf))
               ((eq? tag 'any) (or (not (cadr node)) (< (char->integer c) 128)))
               ((eq? tag 'nonl)
                (and (not (char=? c #\newline)) (not (char=? c #\return))
                     (or (not (cadr node)) (< (char->integer c) 128))))
               ((eq? tag 'class) (%match-class c (cadr node) cf (caddr node)))
               ((eq? tag 'range) (%match-range c (cadr node) cf))
               ((eq? tag 'chars) (%match-chars c (cadr node) cf))
               ;; A one-character string is a <cset-sre>; longer ones cannot
               ;; appear in set position.
               ((eq? tag 'lit)
                (and (= (string-length (cadr node)) 1)
                     (%cm c (string-ref (cadr node) 0) cf)))
               ((eq? tag 'nocase) (%match-one (cadr node) str pos end #t))
               ((eq? tag 'case) (%match-one (cadr node) str pos end #f))
               ((eq? tag 'alt)
                (let loop ((ps (cdr node)))
                  (and (pair? ps)
                       (or (%match-one (car ps) str pos end cf) (loop (cdr ps))))))
               ;; (~ x) is (- any x), so in an ASCII context it is ASCII-only.
               ((eq? tag 'compl)
                (and (not (%match-one (cadr node) str pos end cf))
                     (or (not (caddr node)) (< (char->integer c) 128))))
               ((eq? tag 'cand)
                (%every (lambda (n) (%match-one n str pos end cf)) (cdr node)))
               ((eq? tag 'cdiff)
                (and (%match-one (cadr node) str pos end cf)
                     (not (%match-one (caddr node) str pos end cf))))
               (else #f)))))

    ;; A node that always consumes exactly one character and captures nothing
    ;; can be repeated by scanning, so `(* any)' over a long string costs no
    ;; stack -- only the general path below nests one frame per iteration.
    (define (%single-char-node? node)
      (let ((tag (car node)))
        (cond
          ((memq tag '(chr any nonl class range chars)) #t)
          ((eq? tag 'lit) (= (string-length (cadr node)) 1))
          ((memq tag '(nocase case compl)) (%single-char-node? (cadr node)))
          ((memq tag '(alt cand cdiff)) (%every %single-char-node? (cdr node)))
          (else #f))))

    (define (%every pred ls)
      (or (null? ls) (and (pred (car ls)) (%every pred (cdr ls)))))

    ;; Binary search of a flat #(lo hi lo hi ...) codepoint range table.
    (define (%in-table? tbl cp)
      (let loop ((lo 0) (hi (quotient (vector-length tbl) 2)))
        (and (< lo hi)
             (let* ((mid (quotient (+ lo hi) 2))
                    (i (* mid 2)))
               (cond
                 ((< cp (vector-ref tbl i)) (loop lo mid))
                 ((> cp (vector-ref tbl (+ i 1))) (loop (+ mid 1) hi))
                 (else #t))))))

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

    (define (%run-seq parts str start pos end groups cf k)
      (if (null? parts) (k pos groups)
          (%run (car parts) str start pos end groups cf
                (lambda (p g) (%run-seq (cdr parts) str start p end g cf k)))))

    (define (%run-alt parts str start pos end groups cf k)
      (if (null? parts) #f
          (or (%run (car parts) str start pos end groups cf k)
              (%run-alt (cdr parts) str start pos end groups cf k))))

    ;; (rep lo hi body greedy?); hi of #f means unbounded. The (> p pos)
    ;; guard on optional iterations keeps a nullable body from looping.
    (define (%run-rep lo hi inner str start pos end groups cf greedy k)
      (if (%single-char-node? inner)
          (%run-rep1 lo hi inner str pos end groups cf greedy k)
          (cond
            ((> lo 0)
             (%run inner str start pos end groups cf
                   (lambda (p g)
                     (%run-rep (- lo 1) (and hi (- hi 1)) inner
                               str start p end g cf greedy k))))
            ((and hi (<= hi 0)) (k pos groups))
            (else
             (let ((more (lambda ()
                           (%run inner str start pos end groups cf
                                 (lambda (p g)
                                   (and (> p pos)
                                        (%run-rep 0 (and hi (- hi 1)) inner
                                                  str start p end g cf greedy k)))))))
               (if greedy (or (more) (k pos groups)) (or (k pos groups) (more))))))))

    ;; Look-behind asks whether the body matches some span ending exactly at
    ;; `pos'.  Nothing before `start' is visible, matching how SRFI 115 treats
    ;; a start index as the beginning of the string.
    (define (%run-behind inner str start pos cf)
      (let loop ((j pos))
        (cond
          ((< j start) #f)
          ((%run inner str start j pos '() cf
                 (lambda (p g) (and (= p pos) (cons p g)))) #t)
          (else (loop (- j 1))))))

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

    (define (%run compiled str start pos end groups cf k)
      (let ((tag (car compiled)))
        (cond
          ((eq? tag 'lit)
           (let* ((s (cadr compiled)) (slen (string-length s)))
             (and (<= (+ pos slen) end)
                  (let loop ((i 0))
                    (if (= i slen) (k (+ pos slen) groups)
                        (and (%cm (string-ref str (+ pos i)) (string-ref s i) cf)
                             (loop (+ i 1))))))))
          ((memq tag '(chr any nonl class range chars compl cand cdiff))
           (and (%match-one compiled str pos end cf) (k (+ pos 1) groups)))
          ((eq? tag 'assert)
           (and (%run-assert (cadr compiled) str start pos end) (k pos groups)))
          ((eq? tag 'grapheme)
           (and (< pos end) (k (%grapheme-end str pos end) groups)))
          ((eq? tag 'seq) (%run-seq (cdr compiled) str start pos end groups cf k))
          ((eq? tag 'alt) (%run-alt (cdr compiled) str start pos end groups cf k))
          ((eq? tag 'opt)
           (if (caddr compiled)
               (or (%run (cadr compiled) str start pos end groups cf k) (k pos groups))
               (or (k pos groups) (%run (cadr compiled) str start pos end groups cf k))))
          ((eq? tag 'rep)
           (%run-rep (cadr compiled) (caddr compiled) (cadddr compiled)
                     str start pos end groups cf (car (cddddr compiled)) k))
          ((eq? tag 'group)
           (let ((gn (cadr compiled)))
             (%run (caddr compiled) str start pos end groups cf
                   (lambda (p g) (k p (append g (list (list gn pos p))))))))
          ((eq? tag 'nocase) (%run (cadr compiled) str start pos end groups #t k))
          ((eq? tag 'case) (%run (cadr compiled) str start pos end groups #f k))
          ((eq? tag 'look)
           (and (%run (cadr compiled) str start pos end groups cf %run-done)
                (k pos groups)))
          ((eq? tag 'neglook)
           (and (not (%run (cadr compiled) str start pos end groups cf %run-done))
                (k pos groups)))
          ((eq? tag 'lookb)
           (and (%run-behind (cadr compiled) str start pos cf) (k pos groups)))
          ((eq? tag 'neglookb)
           (and (not (%run-behind (cadr compiled) str start pos cf))
                (k pos groups)))
          (else (error "regexp: unknown tag" tag)))))

    ;;; Public API

    (define (regexp re)
      (cond
        ((regexp? re) re)
        ((string? re) (regexp (list ': re)))
        (else
         (let* ((ctx (%make-ctx)) (compiled (%csre re ctx)))
           (%make-regexp re compiled (- (%ctx-groups ctx) 1) (%ctx-names ctx))))))

    (define-syntax rx (syntax-rules () ((rx sre ...) (regexp '(: sre ...)))))
    (define (regexp->sre re) (%regexp-sre (if (regexp? re) re (regexp re))))
    (define (valid-sre? obj) (guard (e (#t #f)) (regexp obj) #t))

    (define (%ensure re) (if (regexp? re) re (regexp re)))

    (define (%build-match str groups num-groups names)
      (let ((vec (make-vector (+ num-groups 1) #f)))
        (for-each (lambda (g)
                    (if (< (car g) (vector-length vec))
                        (vector-set! vec (car g) (list (cadr g) (caddr g))))) groups)
        (%make-regexp-match str vec names)))

    ;; Anchoring the whole string is part of the continuation, not a test on
    ;; the result: a pattern that can match a prefix must be free to backtrack
    ;; until it reaches `end' before regexp-matches gives up.
    (define (%run-anchored r str start end)
      (%run (%regexp-compiled r) str start start end '() #f
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
            (%build-match str (cons (list 0 start end) (cdr m))
                          (%regexp-num-groups r) (%regexp-names r))
            #f)))

    (define (regexp-search re str . rest)
      (let* ((start (if (null? rest) 0 (car rest)))
             (end (if (or (null? rest) (null? (cdr rest))) (string-length str) (cadr rest)))
             (r (%ensure re)))
        (let loop ((i start))
          (if (> i end) #f
              (let ((m (%run (%regexp-compiled r) str start i end '() #f %run-done)))
                (if m (%build-match str (cons (list 0 i (car m)) (cdr m))
                                    (%regexp-num-groups r) (%regexp-names r))
                    (loop (+ i 1))))))))

    (define (regexp-match-count m) (- (vector-length (%match-groups m)) 1))

    ;; A field is a submatch number or, for (-> name ...), its name.  When a
    ;; name is used more than once SRFI 115 asks for the first group of that
    ;; name which actually matched, so resolution needs the match vector.
    (define (%match-ref m field)
      (let ((vec (%match-groups m)))
        (if (symbol? field)
            (let loop ((ns (%match-names m)) (fallback 'none))
              (cond
                ((null? ns)
                 (if (eq? fallback 'none)
                     (error "regexp: unknown submatch name" field)
                     fallback))
                ((not (eq? (caar ns) field)) (loop (cdr ns) fallback))
                ((and (< (cdar ns) (vector-length vec))
                      (vector-ref vec (cdar ns))))
                (else (loop (cdr ns) #f))))
            (vector-ref vec field))))

    (define (regexp-match-submatch m field)
      (let ((g (%match-ref m field)))
        (if g (substring (%match-str m) (car g) (cadr g)) #f)))
    (define (regexp-match-submatch-start m field)
      (let ((g (%match-ref m field))) (if g (car g) #f)))
    (define (regexp-match-submatch-end m field)
      (let ((g (%match-ref m field))) (if g (cadr g) #f)))
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

    ;;; Unicode tables -- generated by tools/gen_srfi115_charsets.py
    ;;; from UCD 15.1.0.  Do not edit by hand.
    ;;;
    ;;; Each table is a flat vector of inclusive [lo hi] codepoint pairs in
    ;;; ascending order, searched by %in-table?.

    ;; general category Lt (10 ranges)
    (define %cs-title-case
      '#(453 453 456 456 459 459 498 498 8072 8079 8088 8095 8104 8111 8124 
         8124 8140 8140 8188 8188))

    ;; general categories Sm, Sc, Sk, So (233 ranges)
    (define %cs-symbol
      '#(36 36 43 43 60 62 94 94 96 96 124 124 126 126 162 166 168 169 172 
         172 174 177 180 180 184 184 215 215 247 247 706 709 722 735 741 747 
         749 749 751 767 885 885 900 901 1014 1014 1154 1154 1421 1423 1542 
         1544 1547 1547 1550 1551 1758 1758 1769 1769 1789 1790 2038 2038 
         2046 2047 2184 2184 2546 2547 2554 2555 2801 2801 2928 2928 3059 
         3066 3199 3199 3407 3407 3449 3449 3647 3647 3841 3843 3859 3859 
         3861 3863 3866 3871 3892 3892 3894 3894 3896 3896 4030 4037 4039 
         4044 4046 4047 4053 4056 4254 4255 5008 5017 5741 5741 6107 6107 
         6464 6464 6622 6655 7009 7018 7028 7036 8125 8125 8127 8129 8141 
         8143 8157 8159 8173 8175 8189 8190 8260 8260 8274 8274 8314 8316 
         8330 8332 8352 8384 8448 8449 8451 8454 8456 8457 8468 8468 8470 
         8472 8478 8483 8485 8485 8487 8487 8489 8489 8494 8494 8506 8507 
         8512 8516 8522 8525 8527 8527 8586 8587 8592 8967 8972 9000 9003 
         9254 9280 9290 9372 9449 9472 10087 10132 10180 10183 10213 10224 
         10626 10649 10711 10716 10747 10750 11123 11126 11157 11159 11263 
         11493 11498 11856 11857 11904 11929 11931 12019 12032 12245 12272 
         12287 12292 12292 12306 12307 12320 12320 12342 12343 12350 12351 
         12443 12444 12688 12689 12694 12703 12736 12771 12783 12783 12800 
         12830 12842 12871 12880 12880 12896 12927 12938 12976 12992 13311 
         19904 19967 42128 42182 42752 42774 42784 42785 42889 42890 43048 
         43051 43062 43065 43639 43641 43867 43867 43882 43883 64297 64297 
         64434 64450 64832 64847 64975 64975 65020 65023 65122 65122 65124 
         65126 65129 65129 65284 65284 65291 65291 65308 65310 65342 65342 
         65344 65344 65372 65372 65374 65374 65504 65510 65512 65518 65532 
         65533 65847 65855 65913 65929 65932 65934 65936 65948 65952 65952 
         66000 66044 67703 67704 68296 68296 71487 71487 73685 73713 92988 
         92991 92997 92997 113820 113820 118608 118723 118784 119029 119040 
         119078 119081 119140 119146 119148 119171 119172 119180 119209 
         119214 119274 119296 119361 119365 119365 119552 119638 120513 
         120513 120539 120539 120571 120571 120597 120597 120629 120629 
         120655 120655 120687 120687 120713 120713 120745 120745 120771 
         120771 120832 121343 121399 121402 121453 121460 121462 121475 
         121477 121478 123215 123215 123647 123647 126124 126124 126128 
         126128 126254 126254 126704 126705 126976 127019 127024 127123 
         127136 127150 127153 127167 127169 127183 127185 127221 127245 
         127405 127462 127490 127504 127547 127552 127560 127568 127569 
         127584 127589 127744 128727 128732 128748 128752 128764 128768 
         128886 128891 128985 128992 129003 129008 129008 129024 129035 
         129040 129095 129104 129113 129120 129159 129168 129197 129200 
         129201 129280 129619 129632 129645 129648 129660 129664 129672 
         129680 129725 129727 129733 129742 129755 129760 129768 129776 
         129784 129792 129938 129940 129994))

    ;; UAX #29 Extend + SpacingMark + ZWJ (317 ranges)
    (define %cs-mark
      '#(768 879 1155 1161 1425 1469 1471 1471 1473 1474 1476 1477 1479 1479 
         1552 1562 1611 1631 1648 1648 1750 1756 1759 1764 1767 1768 1770 
         1773 1809 1809 1840 1866 1958 1968 2027 2035 2045 2045 2070 2073 
         2075 2083 2085 2087 2089 2093 2137 2139 2200 2207 2250 2273 2275 
         2307 2362 2364 2366 2383 2385 2391 2402 2403 2433 2435 2492 2492 
         2494 2500 2503 2504 2507 2509 2519 2519 2530 2531 2558 2558 2561 
         2563 2620 2620 2622 2626 2631 2632 2635 2637 2641 2641 2672 2673 
         2677 2677 2689 2691 2748 2748 2750 2757 2759 2761 2763 2765 2786 
         2787 2810 2815 2817 2819 2876 2876 2878 2884 2887 2888 2891 2893 
         2901 2903 2914 2915 2946 2946 3006 3010 3014 3016 3018 3021 3031 
         3031 3072 3076 3132 3132 3134 3140 3142 3144 3146 3149 3157 3158 
         3170 3171 3201 3203 3260 3260 3262 3268 3270 3272 3274 3277 3285 
         3286 3298 3299 3315 3315 3328 3331 3387 3388 3390 3396 3398 3400 
         3402 3405 3415 3415 3426 3427 3457 3459 3530 3530 3535 3540 3542 
         3542 3544 3551 3570 3571 3633 3633 3635 3642 3655 3662 3761 3761 
         3763 3772 3784 3790 3864 3865 3893 3893 3895 3895 3897 3897 3902 
         3903 3953 3972 3974 3975 3981 3991 3993 4028 4038 4038 4141 4151 
         4153 4158 4182 4185 4190 4192 4209 4212 4226 4226 4228 4230 4237 
         4237 4253 4253 4957 4959 5906 5909 5938 5940 5970 5971 6002 6003 
         6068 6099 6109 6109 6155 6157 6159 6159 6277 6278 6313 6313 6432 
         6443 6448 6459 6679 6683 6741 6750 6752 6752 6754 6754 6757 6780 
         6783 6783 6832 6862 6912 6916 6964 6980 7019 7027 7040 7042 7073 
         7085 7142 7155 7204 7223 7376 7378 7380 7400 7405 7405 7412 7412 
         7415 7417 7616 7679 8204 8205 8400 8432 11503 11505 11647 11647 
         11744 11775 12330 12335 12441 12442 42607 42610 42612 42621 42654 
         42655 42736 42737 43010 43010 43014 43014 43019 43019 43043 43047 
         43052 43052 43136 43137 43188 43205 43232 43249 43263 43263 43302 
         43309 43335 43347 43392 43395 43443 43456 43493 43493 43561 43574 
         43587 43587 43596 43597 43644 43644 43696 43696 43698 43700 43703 
         43704 43710 43711 43713 43713 43755 43759 43765 43766 44003 44010 
         44012 44013 64286 64286 65024 65039 65056 65071 65438 65439 66045 
         66045 66272 66272 66422 66426 68097 68099 68101 68102 68108 68111 
         68152 68154 68159 68159 68325 68326 68900 68903 69291 69292 69373 
         69375 69446 69456 69506 69509 69632 69634 69688 69702 69744 69744 
         69747 69748 69759 69762 69808 69818 69826 69826 69888 69890 69927 
         69940 69957 69958 70003 70003 70016 70018 70067 70080 70089 70092 
         70094 70095 70188 70199 70206 70206 70209 70209 70367 70378 70400 
         70403 70459 70460 70462 70468 70471 70472 70475 70477 70487 70487 
         70498 70499 70502 70508 70512 70516 70709 70726 70750 70750 70832 
         70851 71087 71093 71096 71104 71132 71133 71216 71232 71339 71351 
         71453 71455 71458 71467 71724 71738 71984 71989 71991 71992 71995 
         71998 72000 72000 72002 72003 72145 72151 72154 72160 72164 72164 
         72193 72202 72243 72249 72251 72254 72263 72263 72273 72283 72330 
         72345 72751 72758 72760 72767 72850 72871 72873 72886 73009 73014 
         73018 73018 73020 73021 73023 73029 73031 73031 73098 73102 73104 
         73105 73107 73111 73459 73462 73472 73473 73475 73475 73524 73530 
         73534 73538 78912 78912 78919 78933 92912 92916 92976 92982 94031 
         94031 94033 94087 94095 94098 94180 94180 94192 94193 113821 113822 
         118528 118573 118576 118598 119141 119145 119149 119154 119163 
         119170 119173 119179 119210 119213 119362 119364 121344 121398 
         121403 121452 121461 121461 121476 121476 121499 121503 121505 
         121519 122880 122886 122888 122904 122907 122913 122915 122916 
         122918 122922 123023 123023 123184 123190 123566 123566 123628 
         123631 124140 124143 125136 125142 125252 125258 127995 127999 
         917536 917631 917760 917999))

    ;; UAX #29 Control (19 ranges)
    (define %cs-gcb-control
      '#(0 9 11 12 14 31 127 159 173 173 1564 1564 6158 6158 8203 8203 8206 
         8207 8232 8238 8288 8303 65279 65279 65520 65531 78896 78911 113824 
         113827 119155 119162 917504 917535 917632 917759 918000 921599))

    ;; UAX #29 Prepend (15 ranges)
    (define %cs-prepend
      '#(1536 1541 1757 1757 1807 1807 2192 2193 2274 2274 3406 3406 69821 
         69821 69837 69837 70082 70083 71999 71999 72001 72001 72250 72250 
         72324 72329 73030 73030 73474 73474))

    ))
