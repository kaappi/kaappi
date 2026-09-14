(define-library (srfi 129)
  (import (scheme base) (scheme char))
  (export char-title-case? char-titlecase string-titlecase)
  (begin
    (define titlecase-chars '(
      (#x01C5 #x01C5) (#x01C8 #x01C8) (#x01CB #x01CB) (#x01F2 #x01F2)
      (#x1F88 #x1F88) (#x1F89 #x1F89) (#x1F8A #x1F8A) (#x1F8B #x1F8B)
      (#x1F8C #x1F8C) (#x1F8D #x1F8D) (#x1F8E #x1F8E) (#x1F8F #x1F8F)
      (#x1F98 #x1F98) (#x1F99 #x1F99) (#x1F9A #x1F9A) (#x1F9B #x1F9B)
      (#x1F9C #x1F9C) (#x1F9D #x1F9D) (#x1F9E #x1F9E) (#x1F9F #x1F9F)
      (#x1FA8 #x1FA8) (#x1FA9 #x1FA9) (#x1FAA #x1FAA) (#x1FAB #x1FAB)
      (#x1FAC #x1FAC) (#x1FAD #x1FAD) (#x1FAE #x1FAE) (#x1FAF #x1FAF)
      (#x1FBC #x1FBC) (#x1FCC #x1FCC) (#x1FFC #x1FFC)))

    (define title-single-map (append titlecase-chars '(
      (#x01C4 #x01C5) (#x01C6 #x01C5)
      (#x01C7 #x01C8) (#x01C9 #x01C8)
      (#x01CA #x01CB) (#x01CC #x01CB)
      (#x01F1 #x01F2) (#x01F3 #x01F2))))

    (define title-multiple-map (append title-single-map '(
      (#x00DF #x0053 #x0073)
      (#xFB00 #x0046 #x0066) (#xFB01 #x0046 #x0069)
      (#xFB02 #x0046 #x006C) (#xFB03 #x0046 #x0066 #x0069)
      (#xFB04 #x0046 #x0066 #x006C) (#xFB05 #x0053 #x0074)
      (#xFB06 #x0053 #x0074) (#x0587 #x0535 #x0582)
      (#xFB13 #x0544 #x0576) (#xFB14 #x0544 #x0565)
      (#xFB15 #x0544 #x056B) (#xFB16 #x054E #x0576)
      (#xFB17 #x0544 #x056D) (#x0149 #x02BC #x004E)
      (#x0390 #x0399 #x0308 #x0301) (#x03B0 #x03A5 #x0308 #x0301)
      (#x01F0 #x004A #x030C) (#x1E96 #x0048 #x0331)
      (#x1E97 #x0054 #x0308) (#x1E98 #x0057 #x030A)
      (#x1E99 #x0059 #x030A) (#x1E9A #x0041 #x02BE)
      (#x1F50 #x03A5 #x0313) (#x1F52 #x03A5 #x0313 #x0300)
      (#x1F54 #x03A5 #x0313 #x0301) (#x1F56 #x03A5 #x0313 #x0342)
      (#x1FB6 #x0391 #x0342) (#x1FC6 #x0397 #x0342)
      (#x1FD2 #x0399 #x0308 #x0300) (#x1FD3 #x0399 #x0308 #x0301)
      (#x1FD6 #x0399 #x0342) (#x1FD7 #x0399 #x0308 #x0342)
      (#x1FE2 #x03A5 #x0308 #x0300) (#x1FE3 #x03A5 #x0308 #x0301)
      (#x1FE4 #x03A1 #x0313) (#x1FE6 #x03A5 #x0342)
      (#x1FE7 #x03A5 #x0308 #x0342) (#x1FF6 #x03A9 #x0342)
      (#x1FB2 #x1FBA #x0345) (#x1FB4 #x0386 #x0345)
      (#x1FC2 #x1FCA #x0345) (#x1FC4 #x0389 #x0345)
      (#x1FF2 #x1FFA #x0345) (#x1FF4 #x038F #x0345)
      (#x1FB7 #x0391 #x0342 #x0345) (#x1FC7 #x0397 #x0342 #x0345)
      (#x1FF7 #x03A9 #x0342 #x0345))))

    (define lower-multiple-map '(
      (#x0130 #x0069 #x0307)))

    (define (char-title-case? ch)
      (let ((cp (char->integer ch)))
        (if (assv cp titlecase-chars) #t #f)))

    (define (char-titlecase ch)
      (let ((result (assv (char->integer ch) title-single-map)))
        (if result
            (integer->char (cadr result))
            (char-upcase ch))))

    (define (char-caseless? ch)
      (not (or (char-lower-case? ch) (char-upper-case? ch) (char-title-case? ch))))

    (define (string-titlecase str)
      (let loop ((n 0) (result '()))
        (if (= n (string-length str))
            (list->string (map integer->char (reverse result)))
            (let* ((ch (string-ref str n))
                   (cp (char->integer ch)))
              (if (or (= n 0) (char-caseless? (string-ref str (- n 1))))
                  (let ((multi (assv cp title-multiple-map)))
                    (if multi
                        (loop (+ n 1) (append (reverse (cdr multi)) result))
                        (loop (+ n 1) (cons (char->integer (char-upcase ch)) result))))
                  (let ((multi (assv cp lower-multiple-map)))
                    (if multi
                        (loop (+ n 1) (append (reverse (cdr multi)) result))
                        (loop (+ n 1) (cons (char->integer (char-downcase ch)) result)))))))))))
