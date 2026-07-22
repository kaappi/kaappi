;;; SRFI 180 — JSON
;;;
;;; A JSON (RFC 8259) reader/writer built around a generator/accumulator
;;; abstraction: `json-generator` turns JSON text into a stream of events
;;; (an object's key/value pairs come through like a property list, keys
;;; always strings), `json-fold` is a generic "foldts"-style (Kiselyov)
;;; iterator over that same event stream with caller-supplied start/end/
;;; value callbacks, and `json-read`/`json-write` are the convenience,
;;; port-based entry points built on top — the ones most callers actually
;;; use. `json-accumulator` is the writer-side mirror of `json-generator`:
;;; a procedure that consumes the same event vocabulary and serializes it.
;;;
;;; Design decisions and spec ambiguities:
;;;
;;; - Generator/accumulator base: Kaappi already has SRFI 158
;;;   (`lib/srfi/158.sld`), so this library builds directly on it rather
;;;   than reinventing a trampoline: `json-generator` is
;;;   `make-coroutine-generator` wrapped around a recursive-descent parser
;;;   that calls `yield` once per token (call/cc suspends/resumes the
;;;   parse between events), and `json-accumulator` is `make-accumulator`
;;;   with a small nesting-stack `kons` and a no-op `finalize` (so feeding
;;;   the returned procedure an eof-object cleanly finishes a write, per
;;;   the SRFI 158 accumulator convention). The reference implementation
;;;   avoids a SRFI 158 dependency (it hand-rolls its own trampoline), but
;;;   this codebase already depends on 158 from other ports (e.g.
;;;   `(srfi 225)`), so reusing it here is the idiomatic choice.
;;;
;;; - Type mapping (from the spec text): `null` <-> the symbol `null`
;;;   (`json-null?` tests for it; there is no `json-null` value procedure
;;;   — the spec exports only the predicate), `true`/`false` <-> `#t`/`#f`,
;;;   number <-> number, string <-> string, array <-> vector, object <->
;;;   an association list keyed by symbols.
;;;
;;; - Duplicate object keys: the spec text never mentions this case. This
;;;   implementation preserves every key/value pair, in original
;;;   left-to-right order, with no deduplication — matching the plist-like
;;;   shape the spec itself describes for the event stream. `assq`/`assoc`
;;;   on the resulting alist therefore return the *first* occurrence.
;;;
;;; - Numbers: read by validating the strict RFC 8259 grammar character by
;;;   character while scanning (no leading zeros, a digit is mandatory
;;;   after '.', digits are mandatory in an exponent), then handing the
;;;   validated substring to `string->number` — so exactness falls out of
;;;   Kaappi's own numeric-literal rules for free: a bare digit sequence
;;;   reads as an exact integer (arbitrary precision), anything with a
;;;   decimal point or exponent reads as inexact. For writing, exact
;;;   integers and finite non-NaN inexact reals are the only numbers
;;;   accepted (per spec: "must not be complex, infinite, NaN, or exact
;;;   rationals that are not integers"); `(number->string n)` was checked
;;;   empirically against a wide range of magnitudes (very large/small,
;;;   scientific notation, negative) and always already produces valid
;;;   JSON number syntax, so no extra reformatting is needed.
;;;
;;; - Strings: reading handles all six short escapes plus `\uXXXX`,
;;;   including combining a high/low UTF-16 surrogate pair into one
;;;   astral codepoint. An unescaped control character (< U+0020) is
;;;   rejected per RFC 8259, and a lone/unpaired surrogate escape is
;;;   rejected as malformed JSON (there is no valid Unicode scalar value
;;;   for it). Writing escapes '"', '\\', the six short escapes, and any
;;;   other control character as `\u00XX`; everything else (including all
;;;   non-ASCII text) is written as literal UTF-8, which is valid JSON.
;;;
;;; - `json-lines-read`/`json-sequence-read` keep *one* persistent
;;;   character source across repeated top-level reads (skipping
;;;   newline/whitespace, and additionally the RS byte for sequences,
;;;   between records) rather than re-resolving the `port-or-generator`
;;;   argument per record. This matters when the source is a raw
;;;   character generator rather than a port: a top-level JSON number has
;;;   no explicit terminator, so parsing one may leave an already-peeked
;;;   lookahead character buffered, and that buffer must survive into the
;;;   next record's read. A port doesn't need this care since
;;;   `peek-char`/`read-char` already persist across separate top-level
;;;   reads on the same port.
;;;
;;; - Known interface limitation: calling the public `json-read` (or
;;;   `json-generator`/`json-fold`) repeatedly *by hand* on the same raw
;;;   character generator (never on a port) can lose exactly one
;;;   lookahead character, in the one edge case of a bare top-level
;;;   number immediately followed by more data with no separator — the
;;;   generator interface has no push-back operation to hand that
;;;   character back once the call that peeked it has already returned.
;;;   This is unreachable through this library's own
;;;   `json-lines-read`/`json-sequence-read` (which never re-resolve their
;;;   source) and through any port-based use, which is the primary case
;;;   the spec itself describes ("a textual input port ... whose default
;;;   value is `(current-input-port)`"), so it is accepted as a documented
;;;   limitation rather than special-cased away.

(define-library (srfi 180)
  (import (scheme base) (scheme inexact) (srfi 158))
  (export json-number-of-character-limit
          json-nesting-depth-limit
          json-null?
          json-error?
          json-error-reason
          json-fold
          json-generator
          json-read
          json-lines-read
          json-sequence-read
          json-accumulator
          json-write)
  (begin

    ;;; ---------------------------------------------------------------
    ;;; Errors
    ;;; ---------------------------------------------------------------

    (define-record-type <json-error>
      (%make-json-error reason)
      json-error?
      (reason json-error-reason))

    (define (%json-error reason)
      (raise (%make-json-error reason)))

    ;;; ---------------------------------------------------------------
    ;;; Limits
    ;;; ---------------------------------------------------------------

    (define json-nesting-depth-limit (make-parameter +inf.0))
    (define json-number-of-character-limit (make-parameter +inf.0))

    (define (%check-depth! new-depth)
      (when (> new-depth (json-nesting-depth-limit))
        (%json-error "json: nesting depth limit exceeded")))

    ;;; ---------------------------------------------------------------
    ;;; null
    ;;; ---------------------------------------------------------------

    (define (json-null? obj) (eq? obj 'null))

    ;;; ---------------------------------------------------------------
    ;;; Character source: wraps either a textual input port or a
    ;;; generator of characters behind one peek1/read1 interface. Ports
    ;;; use their own native peek-char/read-char (so no extra buffering
    ;;; is needed, and lookahead correctly persists across independent
    ;;; top-level reads on the same port); generators get a one-slot
    ;;; pushback buffer since the generator protocol has no native peek.
    ;;; `count` tracks characters consumed for the *current* JSON text,
    ;;; reset at the start of each top-level parse, to enforce
    ;;; `json-number-of-character-limit`.
    ;;; ---------------------------------------------------------------

    (define-record-type <json-source>
      (%raw-make-source kind obj pending count)
      %json-source?
      (kind %source-kind)
      (obj %source-obj)
      (pending %source-pending %source-pending-set!)
      (count %source-count %source-count-set!))

    (define (%make-source obj)
      (if (input-port? obj)
          (%raw-make-source 'port obj #f 0)
          (%raw-make-source 'generator obj #f 0)))

    (define (%source-reset-count! source) (%source-count-set! source 0))

    (define (%peek1 source)
      (if (eq? (%source-kind source) 'port)
          (peek-char (%source-obj source))
          (or (%source-pending source)
              (let ((c ((%source-obj source))))
                (%source-pending-set! source c)
                c))))

    (define (%read1 source)
      (let ((c (if (eq? (%source-kind source) 'port)
                   (read-char (%source-obj source))
                   (let ((p (%source-pending source)))
                     (if p
                         (begin (%source-pending-set! source #f) p)
                         ((%source-obj source)))))))
        (when (not (eof-object? c))
          (%source-count-set! source (+ 1 (%source-count source)))
          (when (> (%source-count source) (json-number-of-character-limit))
            (%json-error "json: number-of-character limit exceeded")))
        c))

    (define (%resolve-input opt)
      (cond ((null? opt) (current-input-port))
            ((null? (cdr opt)) (car opt))
            (else (error "json: at most one port-or-generator argument expected"))))

    ;;; ---------------------------------------------------------------
    ;;; Lexical helpers shared by both the direct value reader and the
    ;;; event tokenizer.
    ;;; ---------------------------------------------------------------

    (define (%json-whitespace? c)
      (and (char? c)
           (or (eqv? c #\space) (eqv? c #\tab) (eqv? c #\newline) (eqv? c #\return))))

    (define (%skip-ws source)
      (let loop ()
        (when (%json-whitespace? (%peek1 source))
          (%read1 source)
          (loop))))

    (define (%json-digit? c) (and (char? c) (char>=? c #\0) (char<=? c #\9)))
    (define (%json-digit19? c) (and (char? c) (char>=? c #\1) (char<=? c #\9)))

    (define (%hex-digit-value c)
      (cond
        ((and (char? c) (char>=? c #\0) (char<=? c #\9)) (- (char->integer c) (char->integer #\0)))
        ((and (char? c) (char>=? c #\a) (char<=? c #\f)) (+ 10 (- (char->integer c) (char->integer #\a))))
        ((and (char? c) (char>=? c #\A) (char<=? c #\F)) (+ 10 (- (char->integer c) (char->integer #\A))))
        (else #f)))

    ;; Consume exactly the characters of `s`, erroring if the source
    ;; doesn't match — used for the "true"/"false"/"null" bareword tokens.
    (define (%expect-literal source s)
      (string-for-each
        (lambda (expected)
          (let ((c (%read1 source)))
            (if (not (eqv? c expected))
                (%json-error (string-append "json: invalid literal, expected \"" s "\"")))))
        s))

    ;;; ---------------------------------------------------------------
    ;;; String reading (shared: values and object keys)
    ;;; ---------------------------------------------------------------

    (define (%read-hex4 source)
      (let loop ((i 0) (acc 0))
        (if (= i 4)
            acc
            (let ((c (%read1 source)))
              (cond
                ((eof-object? c) (%json-error "json: unterminated \\u escape"))
                ((%hex-digit-value c) => (lambda (v) (loop (+ i 1) (+ (* acc 16) v))))
                (else (%json-error "json: invalid hex digit in \\u escape")))))))

    (define (%read-json-unicode-escape source chars)
      (let ((cp (%read-hex4 source)))
        (cond
          ((and (>= cp #xD800) (<= cp #xDBFF))
           (if (and (eqv? (%read1 source) #\\) (eqv? (%read1 source) #\u))
               (let ((lo (%read-hex4 source)))
                 (if (and (>= lo #xDC00) (<= lo #xDFFF))
                     (cons (integer->char (+ #x10000 (* (- cp #xD800) #x400) (- lo #xDC00))) chars)
                     (%json-error "json: invalid low surrogate in \\u escape pair")))
               (%json-error "json: unpaired high surrogate in \\u escape")))
          ((and (>= cp #xDC00) (<= cp #xDFFF))
           (%json-error "json: unpaired low surrogate in \\u escape"))
          (else (cons (integer->char cp) chars)))))

    (define (%read-json-escape source chars)
      (let ((e (%read1 source)))
        (cond
          ((eof-object? e) (%json-error "json: unterminated escape sequence"))
          ((eqv? e #\") (cons #\" chars))
          ((eqv? e #\\) (cons #\\ chars))
          ((eqv? e #\/) (cons #\/ chars))
          ((eqv? e #\b) (cons #\backspace chars))
          ((eqv? e #\f) (cons (integer->char #x0c) chars))
          ((eqv? e #\n) (cons #\newline chars))
          ((eqv? e #\r) (cons #\return chars))
          ((eqv? e #\t) (cons #\tab chars))
          ((eqv? e #\u) (%read-json-unicode-escape source chars))
          (else (%json-error (string-append "json: invalid escape sequence \\" (string e)))))))

    ;; Assumes the current character is the opening '"'.
    (define (%read-json-string source)
      (%read1 source)
      (let loop ((chars '()))
        (let ((c (%read1 source)))
          (cond
            ((eof-object? c) (%json-error "json: unterminated string"))
            ((eqv? c #\") (list->string (reverse chars)))
            ((eqv? c #\\) (loop (%read-json-escape source chars)))
            ((< (char->integer c) #x20)
             (%json-error "json: unescaped control character in string"))
            (else (loop (cons c chars)))))))

    (define (%read-json-key source)
      (%skip-ws source)
      (if (eqv? (%peek1 source) #\")
          (%read-json-string source)
          (%json-error "json: object key must be a string")))

    ;;; ---------------------------------------------------------------
    ;;; Number reading (shared: values only, numbers can't be keys)
    ;;; ---------------------------------------------------------------

    (define (%take-digits! source take!)
      (let loop ()
        (when (%json-digit? (%peek1 source))
          (take!)
          (loop))))

    (define (%take-digits1! source take! what)
      (if (%json-digit? (%peek1 source))
          (begin (take!) (%take-digits! source take!))
          (%json-error (string-append "json: invalid number, expected a digit " what))))

    (define (%read-json-number source)
      (let ((chars '()))
        (define (take!) (set! chars (cons (%read1 source) chars)))
        (when (eqv? (%peek1 source) #\-) (take!))
        (cond
          ((eqv? (%peek1 source) #\0) (take!))
          ((%json-digit19? (%peek1 source)) (take!) (%take-digits! source take!))
          (else (%json-error "json: invalid number, expected a digit")))
        (when (eqv? (%peek1 source) #\.)
          (take!)
          (%take-digits1! source take! "after the decimal point"))
        (when (memv (%peek1 source) '(#\e #\E))
          (take!)
          (when (memv (%peek1 source) '(#\+ #\-)) (take!))
          (%take-digits1! source take! "in the exponent"))
        (let ((s (list->string (reverse chars))))
          (or (string->number s) (%json-error (string-append "json: invalid number syntax: " s))))))

    ;;; ---------------------------------------------------------------
    ;;; Direct recursive-descent reader: builds Scheme values straight
    ;;; away (vectors for arrays, alists for objects). Used by json-read,
    ;;; json-lines-read and json-sequence-read.
    ;;; ---------------------------------------------------------------

    (define (%read-json-value source depth)
      (%skip-ws source)
      (let ((c (%peek1 source)))
        (cond
          ((eof-object? c) (%json-error "json: unexpected end of input"))
          ((eqv? c #\[) (%read1 source) (%read-json-array source depth))
          ((eqv? c #\{) (%read1 source) (%read-json-object source depth))
          ((eqv? c #\") (%read-json-string source))
          ((eqv? c #\t) (%expect-literal source "true") #t)
          ((eqv? c #\f) (%expect-literal source "false") #f)
          ((eqv? c #\n) (%expect-literal source "null") 'null)
          ((or (%json-digit? c) (eqv? c #\-)) (%read-json-number source))
          (else (%json-error (string-append "json: unexpected character '" (string c) "'"))))))

    (define (%read-json-array source depth)
      (%check-depth! (+ depth 1))
      (%skip-ws source)
      (if (eqv? (%peek1 source) #\])
          (begin (%read1 source) (vector))
          (let loop ((acc '()))
            (let ((v (%read-json-value source (+ depth 1))))
              (%skip-ws source)
              (let ((sep (%read1 source)))
                (cond
                  ((eqv? sep #\,) (%skip-ws source) (loop (cons v acc)))
                  ((eqv? sep #\]) (list->vector (reverse (cons v acc))))
                  (else (%json-error "json: expected ',' or ']' in array"))))))))

    (define (%read-json-object source depth)
      (%check-depth! (+ depth 1))
      (%skip-ws source)
      (if (eqv? (%peek1 source) #\})
          (begin (%read1 source) '())
          (let loop ((acc '()))
            (%skip-ws source)
            (let ((k (%read-json-key source)))
              (%skip-ws source)
              (unless (eqv? (%read1 source) #\:)
                (%json-error "json: expected ':' after object key"))
              (%skip-ws source)
              (let ((v (%read-json-value source (+ depth 1))))
                (%skip-ws source)
                (let ((sep (%read1 source)))
                  (cond
                    ((eqv? sep #\,) (loop (cons (cons (string->symbol k) v) acc)))
                    ((eqv? sep #\}) (reverse (cons (cons (string->symbol k) v) acc)))
                    (else (%json-error "json: expected ',' or '}' in object")))))))))

    ;; Like R7RS `read`: if there is nothing left to read (only, at most,
    ;; trailing whitespace), return an eof-object rather than raising --
    ;; only EOF encountered *while already parsing* a value (a genuinely
    ;; truncated JSON text) is an error. This is what lets a port be read
    ;; from repeatedly, R7RS-`read`-style, until exhausted.
    (define (%read-toplevel-value source)
      (%source-reset-count! source)
      (%skip-ws source)
      (if (eof-object? (%peek1 source))
          (eof-object)
          (%read-json-value source 0)))

    (define (json-read . opt)
      (%read-toplevel-value (%make-source (%resolve-input opt))))

    ;;; ---------------------------------------------------------------
    ;;; json-lines-read / json-sequence-read: repeated top-level reads
    ;;; over one persistent source (see header comment for why).
    ;;; ---------------------------------------------------------------

    (define (json-lines-read . opt)
      (let ((source (%make-source (%resolve-input opt))))
        (lambda ()
          (%skip-ws source)
          (if (eof-object? (%peek1 source))
              (eof-object)
              (%read-toplevel-value source)))))

    ;; RFC 7464 JSON text sequences: each record is prefixed by ASCII RS
    ;; (U+001E) and conventionally followed by a newline; both are treated
    ;; leniently here as skippable separators between records.
    (define (%skip-record-separators source)
      (let loop ()
        (let ((c (%peek1 source)))
          (when (or (%json-whitespace? c) (eqv? c (integer->char #x1e)))
            (%read1 source)
            (loop)))))

    (define (json-sequence-read . opt)
      (let ((source (%make-source (%resolve-input opt))))
        (lambda ()
          (%skip-record-separators source)
          (if (eof-object? (%peek1 source))
              (eof-object)
              (%read-toplevel-value source)))))

    ;;; ---------------------------------------------------------------
    ;;; Event tokenizer: yields 'array-start 'array-end 'object-start
    ;;; 'object-end null/boolean/number/string tokens, via SRFI 158's
    ;;; make-coroutine-generator. Object key/value pairs come through
    ;;; like a plist (a key, a string, is always immediately followed by
    ;;; its value). Backs json-generator and, through it, json-fold.
    ;;; ---------------------------------------------------------------

    (define (%tokenize-value source yield depth)
      (%skip-ws source)
      (let ((c (%peek1 source)))
        (cond
          ((eof-object? c) (%json-error "json: unexpected end of input"))
          ((eqv? c #\[) (%read1 source) (%tokenize-array source yield depth))
          ((eqv? c #\{) (%read1 source) (%tokenize-object source yield depth))
          ((eqv? c #\") (yield (%read-json-string source)))
          ((eqv? c #\t) (%expect-literal source "true") (yield #t))
          ((eqv? c #\f) (%expect-literal source "false") (yield #f))
          ((eqv? c #\n) (%expect-literal source "null") (yield 'null))
          ((or (%json-digit? c) (eqv? c #\-)) (yield (%read-json-number source)))
          (else (%json-error (string-append "json: unexpected character '" (string c) "'"))))))

    (define (%tokenize-array source yield depth)
      (%check-depth! (+ depth 1))
      (yield 'array-start)
      (%skip-ws source)
      (if (eqv? (%peek1 source) #\])
          (begin (%read1 source) (yield 'array-end))
          (let loop ()
            (%tokenize-value source yield (+ depth 1))
            (%skip-ws source)
            (let ((sep (%read1 source)))
              (cond
                ((eqv? sep #\,) (%skip-ws source) (loop))
                ((eqv? sep #\]) (yield 'array-end))
                (else (%json-error "json: expected ',' or ']' in array")))))))

    (define (%tokenize-object source yield depth)
      (%check-depth! (+ depth 1))
      (yield 'object-start)
      (%skip-ws source)
      (if (eqv? (%peek1 source) #\})
          (begin (%read1 source) (yield 'object-end))
          (let loop ()
            (%skip-ws source)
            (yield (%read-json-key source))
            (%skip-ws source)
            (unless (eqv? (%read1 source) #\:)
              (%json-error "json: expected ':' after object key"))
            (%skip-ws source)
            (%tokenize-value source yield (+ depth 1))
            (%skip-ws source)
            (let ((sep (%read1 source)))
              (cond
                ((eqv? sep #\,) (%skip-ws source) (loop))
                ((eqv? sep #\}) (yield 'object-end))
                (else (%json-error "json: expected ',' or '}' in object")))))))

    ;; As with %read-toplevel-value: nothing left to read (past optional
    ;; whitespace) means the coroutine body yields nothing at all, so the
    ;; generator's very first call correctly returns an eof-object instead
    ;; of raising.
    (define (json-generator . opt)
      (let ((source (%make-source (%resolve-input opt))))
        (%source-reset-count! source)
        (make-coroutine-generator
          (lambda (yield)
            (%skip-ws source)
            (unless (eof-object? (%peek1 source))
              (%tokenize-value source yield 0))))))

    ;;; ---------------------------------------------------------------
    ;;; json-fold: a "foldts" (Kiselyov) walk over one json-generator's
    ;;; event stream. `proc` folds every scalar token *and* the finished
    ;;; value of a just-closed structure into the current seed;
    ;;; `array-start`/`object-start` open a fresh inner seed for a
    ;;; structure's children, `array-end`/`object-end` turn the
    ;;; accumulated inner seed into that structure's own value once it
    ;;; closes. Parses at most one top-level JSON value, like
    ;;; json-generator itself.
    ;;; ---------------------------------------------------------------

    (define (json-fold proc array-start array-end object-start object-end seed . opt)
      (let ((gen (apply json-generator opt)))
        (define (walk-value tok seed)
          (cond
            ((eq? tok 'array-start)
             (proc (walk-seq (array-start seed) 'array-end array-end) seed))
            ((eq? tok 'object-start)
             (proc (walk-seq (object-start seed) 'object-end object-end) seed))
            (else (proc tok seed))))
        (define (walk-seq inner end-tok end-proc)
          (let ((tok (gen)))
            (if (eq? tok end-tok)
                (end-proc inner)
                (walk-seq (walk-value tok inner) end-tok end-proc))))
        (let ((tok (gen)))
          (if (eof-object? tok) seed (walk-value tok seed)))))

    ;;; ---------------------------------------------------------------
    ;;; Writer-side validation and formatting
    ;;; ---------------------------------------------------------------

    (define (%every? pred lst)
      (or (null? lst) (and (pred (car lst)) (%every? pred (cdr lst)))))

    (define (%vector-every? pred vec)
      (let ((n (vector-length vec)))
        (let loop ((i 0))
          (or (= i n) (and (pred (vector-ref vec i)) (loop (+ i 1)))))))

    ;; Must be an exact integer (arbitrary precision) or a finite,
    ;; non-NaN inexact real. Complex numbers are excluded by `real?`;
    ;; exact non-integer rationals (e.g. 1/2) are excluded explicitly.
    (define (%json-number? obj)
      (and (number? obj)
           (real? obj)
           (if (exact? obj)
               (integer? obj)
               (and (not (infinite? obj)) (not (nan? obj))))))

    (define (%json-alist-entry? entry)
      (and (pair? entry) (symbol? (car entry)) (%json-serializable? (cdr entry))))

    (define (%json-serializable? obj)
      (cond
        ((eq? obj 'null) #t)
        ((boolean? obj) #t)
        ((%json-number? obj) #t)
        ((string? obj) #t)
        ((vector? obj) (%vector-every? %json-serializable? obj))
        ((list? obj) (%every? %json-alist-entry? obj))
        (else #f)))

    (define (%hex4 cp)
      (let ((s (number->string cp 16)))
        (string-append (make-string (- 4 (string-length s)) #\0) s)))

    (define (%json-escape-char c)
      (let ((cp (char->integer c)))
        (cond
          ((eqv? c #\") "\\\"")
          ((eqv? c #\\) "\\\\")
          ((= cp 8) "\\b")
          ((= cp 9) "\\t")
          ((= cp 10) "\\n")
          ((= cp 12) "\\f")
          ((= cp 13) "\\r")
          ((< cp #x20) (string-append "\\u" (%hex4 cp)))
          (else (string c)))))

    (define (%emit-json-string! s emit!)
      (emit! "\"")
      (string-for-each (lambda (c) (emit! (%json-escape-char c))) s)
      (emit! "\""))

    ;;; ---------------------------------------------------------------
    ;;; json-accumulator: a nesting-stack state machine driving
    ;;; SRFI 158's make-accumulator. Each frame is (kind need-comma?
    ;;; awaiting): kind is 'array or 'object; need-comma? says whether a
    ;;; "," is needed before the next key/element at this level;
    ;;; awaiting is 'key or 'value for an object (unused for an array).
    ;;; ---------------------------------------------------------------

    (define (%frame kind comma awaiting) (list kind comma awaiting))
    (define (%frame-kind f) (car f))
    (define (%frame-comma? f) (cadr f))
    (define (%frame-awaiting f) (caddr f))

    ;; A value (scalar, or a structure that just closed) was completed at
    ;; the new top frame of `stack` (post-pop, for a just-closed
    ;; structure; unchanged, for a scalar) -- arm it to expect a comma
    ;; before its next sibling, and (for an object) a key next.
    (define (%mark-value-done stack)
      (if (null? stack)
          stack
          (let ((f (car stack)))
            (cons (if (eq? (%frame-kind f) 'object)
                      (%frame 'object #t 'key)
                      (%frame 'array #t #f))
                  (cdr stack)))))

    ;; Shared prologue for anything playing the role of "a value" (a
    ;; scalar, or the start of a nested structure): emits a leading comma
    ;; when a sibling already preceded it, and rejects a structure
    ;; offered where an object key (a string) is required. An object's
    ;; *value* slot (awaiting = 'value) never needs a comma -- the colon
    ;; already separates it from its key -- so only an array or an
    ;; object awaiting a key ever consults need-comma?.
    (define (%acc-open-value! stack emit!)
      (unless (null? stack)
        (let ((f (car stack)))
          (cond
            ((eq? (%frame-kind f) 'object)
             (when (eq? (%frame-awaiting f) 'key)
               (%json-error "json-accumulator: an object key must be a string")))
            ((%frame-comma? f) (emit! ","))))))

    (define (%acc-emit-scalar-text! token emit!)
      (cond
        ((eq? token 'null) (emit! "null"))
        ((eq? token #t) (emit! "true"))
        ((eq? token #f) (emit! "false"))
        ((%json-number? token) (emit! (number->string token)))
        ((string? token) (%emit-json-string! token emit!))
        (else (%json-error "json-accumulator: invalid token"))))

    (define (%acc-scalar! token stack emit!)
      (cond
        ((null? stack)
         (%acc-emit-scalar-text! token emit!)
         stack)
        ((and (eq? (%frame-kind (car stack)) 'object)
              (eq? (%frame-awaiting (car stack)) 'key))
         (if (not (string? token))
             (%json-error "json-accumulator: an object key must be a string")
             (let ((f (car stack)))
               (when (%frame-comma? f) (emit! ","))
               (%acc-emit-scalar-text! token emit!)
               (emit! ":")
               (cons (%frame 'object #f 'value) (cdr stack)))))
        (else
         (%acc-open-value! stack emit!)
         (%acc-emit-scalar-text! token emit!)
         (%mark-value-done stack))))

    (define (%accumulate-token! token stack emit!)
      (cond
        ((eq? token 'array-end)
         (if (or (null? stack) (not (eq? (%frame-kind (car stack)) 'array)))
             (%json-error "json-accumulator: array-end does not match an open array")
             (begin (emit! "]") (%mark-value-done (cdr stack)))))
        ((eq? token 'object-end)
         (cond
           ((or (null? stack) (not (eq? (%frame-kind (car stack)) 'object)))
            (%json-error "json-accumulator: object-end does not match an open object"))
           ((eq? (%frame-awaiting (car stack)) 'value)
            (%json-error "json-accumulator: object-end while a value was expected"))
           (else (emit! "}") (%mark-value-done (cdr stack)))))
        ((eq? token 'array-start)
         (%acc-open-value! stack emit!)
         (emit! "[")
         (cons (%frame 'array #f #f) stack))
        ((eq? token 'object-start)
         (%acc-open-value! stack emit!)
         (emit! "{")
         (cons (%frame 'object #f 'key) stack))
        (else (%acc-scalar! token stack emit!))))

    (define (%make-emitter dst)
      (cond
        ((output-port? dst) (lambda (s) (write-string s dst)))
        ((procedure? dst) dst)
        (else (error "json-accumulator: expected an output port or an accumulator procedure" dst))))

    (define (json-accumulator port-or-accumulator)
      (let ((emit! (%make-emitter port-or-accumulator)))
        (make-accumulator
          (lambda (token stack) (%accumulate-token! token stack emit!))
          '()
          (lambda (stack) (if #f #f)))))

    ;;; ---------------------------------------------------------------
    ;;; json-write: validates the whole structure up front (so a bad
    ;;; value deep inside a large structure is rejected before anything
    ;;; is written), then walks it, feeding json-accumulator.
    ;;; ---------------------------------------------------------------

    (define (%resolve-output opt)
      (cond ((null? opt) (current-output-port))
            ((null? (cdr opt)) (car opt))
            (else (error "json-write: at most one port-or-accumulator argument expected"))))

    (define (%write-value! obj acc)
      (cond
        ((vector? obj)
         (acc 'array-start)
         (vector-for-each (lambda (v) (%write-value! v acc)) obj)
         (acc 'array-end))
        ((null? obj)
         (acc 'object-start)
         (acc 'object-end))
        ((and (list? obj) (pair? obj))
         (acc 'object-start)
         (for-each (lambda (kv) (acc (symbol->string (car kv))) (%write-value! (cdr kv) acc)) obj)
         (acc 'object-end))
        (else (acc obj))))

    (define (json-write obj . opt)
      (if (not (%json-serializable? obj))
          (%json-error "json-write: object is not representable as JSON"))
      (let ((acc (json-accumulator (%resolve-output opt))))
        (%write-value! obj acc)
        (acc (eof-object))))))
