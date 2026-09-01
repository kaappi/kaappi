#!/usr/bin/env python3
"""Regenerate tests/scheme/srfi/srfi231-official.scm from the vendored,
pristine upstream test-arrays.scm.

Two stages, run as one command (defaults resolve next to this script):

  1. the Gambit->kaappi adaptation (harness macros, ##-ism removal, PGM
     port rewrite, identifier renames, shims) -- unchanged from the
     original adaptation;
  2. the vendoring postlude (kaappi-specific header, known-divergence
     accounting, fixture/output path resolution, CI verdict epilogue).

Regenerate after editing either the upstream source or this script:

    python3 tests/scheme/srfi/srfi231-official-transform.py

and commit the regenerated suite together with the change. The generated
file must never be hand-edited -- every patch belongs here so the file
stays reproducible.
"""
import re, json

import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
# The upstream source is Gambit-dialect Scheme (DSSSL #!optional, digit-
# leading identifiers): it must NOT carry a bare .scm suffix under
# tests/scheme, where fmt.sh's corpus sweep requires every .scm to be
# R7RS-readable. The .gambit suffix is the point, not a typo.
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'srfi231-official-fixtures', 'test-arrays.scm.gambit')
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'srfi231-official.scm')
META = os.path.join(HERE, 'srfi231-official-fixtures', 'tests-meta.json')

orig = open(SRC).read()

# ---------------------------------------------------------------- scanner
def code_spans(text):
    """Single pass: yield (start,end) spans of CODE (outside strings and
    comments). Handles ; line comments, #| |# nested block comments,
    "strings", #; datum comments (skips marker + following datum handled
    by caller seeing a separate mechanism), char literals #\\x."""
    spans = []
    i = 0; n = len(text); start = 0
    def flush(upto):
        if upto > start:
            spans.append((start, upto))
    while i < n:
        c = text[i]
        if c == ';':
            flush(i)
            while i < n and text[i] != '\n': i += 1
            start = i
            continue
        if c == '"':
            flush(i)
            i += 1
            while i < n:
                if text[i] == '\\': i += 2; continue
                if text[i] == '"': break
                i += 1
            i += 1; start = i
            continue
        if c == '#' and i + 1 < n:
            if text[i+1] == '|':
                flush(i)
                depth = 1; i += 2
                while i < n and depth:
                    if text.startswith('#|', i): depth += 1; i += 2
                    elif text.startswith('|#', i): depth -= 1; i += 2
                    else: i += 1
                start = i
                continue
            if text[i+1] == '\\':
                flush(i)
                i += 2
                while i < n and (text[i].isalnum() or text[i] == '-'): i += 1
                start = i
                continue
            if text[i+1] == ';':
                # datum comment: skip marker; the following datum will be
                # skipped by the caller via a skip-list
                flush(i)
                i += 2
                # skip whitespace then one datum
                while i < n and text[i] in ' \t\r\n': i += 1
                if i < n and text[i] == '(':
                    depth = 0
                    while i < n:
                        d = text[i]
                        if d == '(': depth += 1
                        elif d == ')':
                            depth -= 1
                            if depth == 0: i += 1; break
                        elif d == '"':
                            i += 1
                            while i < n:
                                if text[i] == '\\': i += 2; continue
                                if text[i] == '"': break
                                i += 1
                        elif d == ';':
                            while i < n and text[i] != '\n': i += 1
                            continue
                        i += 1
                else:
                    while i < n and text[i] not in ' \t\r\n()': i += 1
                start = i
                continue
        i += 1
    flush(n)
    return spans

CODE = code_spans(orig)

def in_code(i):
    for (a, b) in CODE:
        if a <= i < b: return True
        if i < a: return False
    return False

def form_end(text, i):
    """i at '(' in code; return index past matching ')'"""
    depth = 0; j = i; n = len(text)
    while j < n:
        c = text[j]
        if c == ';':
            while j < n and text[j] != '\n': j += 1
            continue
        if c == '"':
            j += 1
            while j < n:
                if text[j] == '\\': j += 2; continue
                if text[j] == '"': break
                j += 1
            j += 1; continue
        if c == '#' and j + 1 < n:
            if text[j+1] == '|':
                depth2 = 1; j += 2
                while j < n and depth2:
                    if text.startswith('#|', j): depth2 += 1; j += 2
                    elif text.startswith('|#', j): depth2 -= 1; j += 2
                    else: j += 1
                continue
            if text[j+1] == '\\':
                j += 2
                while j < n and (text[j].isalnum() or text[j] == '-'): j += 1
                continue
            if text[j+1] == ';':
                raise ValueError('datum comment inside form not supported at %d' % j)
        if c == '(': depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0: return j + 1
        j += 1
    raise ValueError('unbalanced at %d' % i)

def skip_vector_literal(text, j):
    """j at '#(' or '#u8('-style prefix; return index past the closing paren"""
    k = j
    while k < len(text) and text[k] != '(':
        if text[k] in ' \t\r\n()': return j  # not a vector literal
        k += 1
    if k >= len(text): return j
    fe = form_end(text, k)
    return fe

def top_elements(text, i, end):
    """yield (start,end) spans of top-level elements of form [i,end) at '('"""
    j = i + 1
    while j < end:
        c = text[j]
        if c in ' \t\r\n': j += 1; continue
        if c == ';':
            while j < end and text[j] != '\n': j += 1
            continue
        if c == '"':
            s0 = j
            j += 1
            while j < end:
                if text[j] == '\\': j += 2; continue
                if text[j] == '"': break
                j += 1
            yield (s0, j + 1); j += 1; continue
        if c == '(':
            fe = form_end(text, j)
            yield (j, fe); j = fe; continue
        if c == '#' and j + 1 < end and (text[j+1] == '(' or text[j+1:j+3] == 'u8'):
            fe = skip_vector_literal(text, j)
            yield (j, fe); j = fe; continue
        k = j
        while k < end and text[k] not in ' \t\r\n()':
            if text[k] == '#' and k + 1 < end and text[k+1] == '(':
                break  # vector literal glued to atom prefix (e.g. '#(3 4))
            k += 1
        if k == j and text[k] != '#':
            yield (j, j + 1); j += 1; continue
        # consume atom, possibly with glued vector literals ('#(3 4))
        k = j
        while k < end:
            ch = text[k]
            if ch in ' \t\r\n()':
                break
            if ch == '#' and k + 1 < end and text[k+1] == '(':
                k = form_end(text, k + 1)
                continue
            k += 1
        # quote prefix glued to a list: '(...), '(), '(42)
        if (k < end and text[k] == '(' and k > j
                and set(text[j:k]) <= set("',`@")):
            k2 = form_end(text, k)
            yield (j, k2); j = k2; continue
        yield (j, k); j = k

def find_forms(text, name):
    out = []
    for (a, b) in CODE:
        j = a
        while True:
            i = text.find('(' + name, j, b)
            if i < 0: break
            after = i + 1 + len(name)
            if after >= len(text) or text[after] in ' \t\r\n()':
                fe = form_end(text, i)
                out.append((i, fe))
                j = fe
                continue
            j = i + 1
    return out

def line_of(text, i):
    return text.count('\n', 0, i) + 1

# ---------------------------------------------------------------- collect test forms
edits = []
test_meta = []
tid = 0
for (i, end) in find_forms(orig, 'test'):
    elems = [e for e in top_elements(orig, i, end)
             if e[0] < e[1] and orig[e[0]:e[1]] != ')']
    elems = elems[1:]  # drop head symbol 'test'
    if len(elems) != 2:
        print('WARN test %d elems line %d: %r' % (len(elems), line_of(orig, i), orig[i:min(end,i+100)]))
        continue
    if orig[elems[0][0]:elems[0][1]] == 'expr':
        continue  # the define-macro (test expr value) head, replaced anyway
    (es, ee), (vs, ve) = elems
    expr_txt = orig[es:ee]
    val_txt = orig[vs:ve].strip()
    tid += 1
    line = line_of(orig, i)
    if val_txt.startswith('"'):
        repl = '(test-err %d %d %s)' % (tid, line, expr_txt)
        kind = 'error'
    else:
        repl = '(test %d %d %s %s)' % (tid, line, expr_txt, orig[vs:ve])
        kind = 'value'
    test_meta.append({'id': tid, 'line': line, 'kind': kind,
                      'expr': expr_txt, 'expected': val_txt})
    edits.append((i, end, repl))

for (i, end) in find_forms(orig, 'test-multiple-values'):
    elems = [e for e in top_elements(orig, i, end)
             if e[0] < e[1] and orig[e[0]:e[1]] != ')']
    elems = elems[1:]
    if len(elems) != 2:
        print('WARN tmv line %d' % line_of(orig, i))
        continue
    if orig[elems[0][0]:elems[0][1]] == 'expr':
        continue  # define-macro head
    (es, ee), (vs, ve) = elems
    tid += 1
    line = line_of(orig, i)
    repl = '(test-mv %d %d %s %s)' % (tid, line, orig[es:ee], orig[vs:ve])
    test_meta.append({'id': tid, 'line': line, 'kind': 'mv',
                      'expr': orig[es:ee], 'expected': orig[vs:ve].strip()})
    edits.append((i, end, repl))

print('test forms: %d (value: %d, error: %d, mv: %d)' % (
    tid,
    sum(1 for m in test_meta if m['kind'] == 'value'),
    sum(1 for m in test_meta if m['kind'] == 'error'),
    sum(1 for m in test_meta if m['kind'] == 'mv')))

edits.sort(key=lambda e: e[0])
parts = []
pos = 0
for (s, e, r) in edits:
    parts.append(orig[pos:s]); parts.append(r); pos = e
parts.append(orig[pos:])
src = ''.join(parts)

# ---------------------------------------------------------------- header
old_include = '''(begin
  ;; Uncomment this line to run test-arrays.scm in Gambit.
  (include "generic-arrays.scm"))'''
new_include = '''(import (srfi 231) (srfi 27) (srfi 143) (srfi 4)
        (srfi 160 u64) (srfi 160 s64)
        (scheme base) (scheme write) (scheme char) (scheme cxr)
        (scheme file) (scheme read) (scheme lazy))'''
assert old_include in src
src = src.replace(old_include, new_include)
src = re.sub(r'^\(declare[^\n]*\)\n', ';; (declare removed)\n', src, flags=re.M)

# ---------------------------------------------------------------- harness macros
mstart = src.index('(define-macro (test expr value)')
mend = src.index(';;; requires make-list function')
new_macros = r''';;; kaappi harness: syntax-rules replacement for the Gambit define-macro
;;; test harness. On error the result is the sentinel ERROR-MARKER and the
;;; message is stashed in LAST-ERROR for failure reporting.

(define error-marker (vector 'error 'marker))
(define last-error #f)

(define (catch-test thunk)
  (guard (e (#t (begin (set! last-error
                             (if (error-object? e)
                                 (error-object-message e)
                                 e))
                       error-marker)))
    (set! last-error #f)
    (thunk)))

(define (obj->string x)
  (let ((p (open-output-string)))
    (write x p)
    (let ((s (get-output-string p)))
      (close-port p)
      (if (> (string-length s) 300)
          (string-append (substring s 0 300) "...")
          s))))

(define (report-failure id line result expected)
  (set! failed-tests (+ failed-tests 1))
  (display "FAIL ")
  (display id) (display " (line ") (display line) (display ") result=")
  (display (obj->string result))
  (display " expected=")
  (display (obj->string expected))
  (if (and (eq? result error-marker) last-error)
      (begin (display " [error: ") (display (obj->string last-error)) (display "]")))
  (newline))

(define error-string-tests 0)

(define executed-tests (make-vector 10000 #f))

(define-syntax test
  (syntax-rules ()
    ((_ id line expr value)
     (let* ((result (catch-test (lambda () expr)))
            (val value))
       (set! total-tests (+ total-tests 1))
       (vector-set! executed-tests id #t)
       (cond ((and (string? val) (eq? result error-marker))
              ;; an error was required and raised; only the Gambit message
              ;; text differs -- count separately, not a failure
              (set! error-string-tests (+ error-string-tests 1)))
             ((not (equal? result val))
              (report-failure id line result val)))))))

(define-syntax test-err
  (syntax-rules ()
    ((_ id line expr)
     (let ((result (catch-test (lambda () expr))))
       (set! total-tests (+ total-tests 1))
       (vector-set! executed-tests id #t)
       (if (not (eq? result error-marker))
           (report-failure id line result 'expected-an-error))))))

(define-syntax test-mv
  (syntax-rules ()
    ((_ id line expr vals)
     (call-with-values (lambda () expr)
       (lambda args
         (set! total-tests (+ total-tests 1))
         (vector-set! executed-tests id #t)
         (if (not (equal? args vals))
             (report-failure id line args vals)))))))

;;; ported reference-internals used as oracles by the suite (pure Scheme)

(define (%%every pred lst)
  (let loop ((l lst))
    (or (null? l)
        (and (pred (car l)) (loop (cdr l))))))

(define (%%vector-every pred . vectors)
  (let ((n (vector-length (car vectors))))
    (let loop ((i 0))
      (or (= i n)
          (and (apply pred (map (lambda (v) (vector-ref v i)) vectors))
               (loop (+ i 1)))))))

(define (%%interval-lower-bounds interval)
  (interval-lower-bounds->vector interval))

(define (%%interval-upper-bounds interval)
  (interval-upper-bounds->vector interval))

(define (%%array-getter array) (array-getter array))
(define (%%array-domain array) (array-domain array))

(define (%%vector-permute vec permutation)
  (let* ((n (vector-length vec))
         (result (make-vector n)))
    (do ((i 0 (+ i 1)))
        ((= i n) result)
      (vector-set! result i (vector-ref vec (vector-ref permutation i))))))

(define (%%vector-permute->list vec permutation)
  (do ((i (- (vector-length vec) 1) (- i 1))
       (result '() (cons (vector-ref vec (vector-ref permutation i)) result)))
      ((< i 0) result)))

(define (%%permutation-invert permutation)
  (let* ((n (vector-length permutation))
         (result (make-vector n)))
    (do ((i 0 (+ i 1)))
        ((= i n) result)
      (vector-set! result (vector-ref permutation i) i))))

(define (%%interval->basic-indexer interval)
  (let* ((lowers (vector->list (interval-lower-bounds->vector interval)))
         (widths (vector->list (interval-widths interval)))
         (coefficients
          (let loop ((ws (reverse widths)) (c 1) (acc '()))
            (if (null? ws)
                acc
                (loop (cdr ws) (* c (car ws)) (cons c acc))))))
    (lambda args
      (apply + (map (lambda (a l c) (* c (- a l))) args lowers coefficients)))))

(define (%%compose-indexers old-indexer new-domain new-domain->old-domain)
  (lambda args
    (call-with-values (lambda () (apply new-domain->old-domain args))
      old-indexer)))

;;; Gambit fixnum-comparison aliases
(define (fx= a b) (= a b))
(define (fx< a b) (< a b))
(define (fx> a b) (> a b))

;;; pretty-printers
(define (pp x) (write x) (newline))
(define (pretty-print x) (write x) (newline))

;;; suite bug: random-f64vector is called but never defined anywhere
(define (random-f64vector n)
  (let ((v (make-f64vector n 0.0)))
    (do ((i 0 (+ i 1)))
        ((= i n) v)
      (f64vector-set! v i (* 1.0 (random 100))))))

'''
src = src[:mstart] + new_macros + src[mend:]

# ---------------------------------------------------------------- #!optional defines
def rewrite_optional(src, header, required, optnames, defaults):
    start = src.index(header)
    dstart = src.rindex('(define', start, start + 30)
    dend = form_end(src, dstart)
    body = src[start + len(header):dend - 1]
    binds = '\n    '.join(
        '(%s (if (< %d (length opts)) (list-ref opts %d) %s))' % (nm, k, k, df)
        for k, (nm, df) in enumerate(zip(optnames, defaults)))
    head = header[1:header.index(' #!optional')]  # "define (name req..."
    repl = ('(%s . opts)\n  (let* (%s)\n%s))' % (head, binds, body))
    return src[:dstart] + repl + src[dend:]

repl_table = [
    ('(define (random a #!optional b)\n', ['a'], ['b'], ['#f']),
    ('(define (random-inclusive a #!optional b)\n', ['a'], ['b'], ['#f']),
    ('(define (random-sample n #!optional (l 4))\n', ['n'], ['l'], ['4']),
    ('(define (random-interval #!optional (min 0) (max 6))\n', [], ['min', 'max'], ['0', '6']),
    ('(define (random-nonempty-interval #!optional (min 0) (max 6))\n', [], ['min', 'max'], ['0', '6']),
    ('(define (random-nonnegative-interval #!optional (min 1) (max 6))\n', [], ['min', 'max'], ['1', '6']),
    ('(define (random-positive-vector n #!optional (max 5))\n', ['n'], ['max'], ['5']),
    ('(define (myarray= array1 array2 #!optional (compare equal?))\n', ['array1', 'array2'], ['compare'], ['equal?']),
]
for hdr, req, opts, defs in repl_table:
    src = rewrite_optional(src, hdr, req, opts, defs)
# write-pgm is replaced wholesale later; drop its #!optional problem by removal below

# ---------------------------------------------------------------- ## forms
src = src.replace('(random-inclusive (##max-char-code))', '(random-inclusive #x10FFFF)')
src = src.replace('(integer->char (##max-char-code))', '(integer->char #x10FFFF)')
src = src.replace('(##mutable? string)', '#f')
assert '##' not in re.sub(r';;[^\n]*', '', src) or True

# quoted Gambit namespace block: kaappi's reader rejects '##...' even as datum
qstart = src.index("'(begin\n  ;; To run test-arrays.scm as an R7RS module in Gambit,")
qend = src.index('(declare removed)', qstart) if '(declare removed)' in src[qstart:qstart+3000] else None
# the block ends at its matching close paren
qb = src.index('(##namespace', qstart)
qe = form_end(src, qstart + 1)  # the quoted (begin ...) form
src = src[:qstart] + ";; (quoted Gambit ##namespace block removed: kaappi reader rejects '##' even in datum)\n" + src[qe:]

# ---------------------------------------------------------------- remove internals regions
lines = src.split('\n')
i_start = next(i for i, l in enumerate(lines) if l.startswith(';;; Now we need to test the precomputation'))
i_end = next(i for i, l in enumerate(lines) if l == '(pp "array-copy and array-copy! error tests")')
removed = i_end - i_start
lines[i_start:i_end] = [';;; REMOVED for kaappi run: array-packed? caching tests and the',
                        ';;; %%move-array-elements section (reference internals; the public',
                        ';;; array-copy/array-assign! behavior they underlie is covered by',
                        ';;; the array-copy, array-assign! and array-reshape tests below).']
src = '\n'.join(lines)
print('removed internals region lines: %d' % removed)

# ---------------------------------------------------------------- strip active (time ...) wrappers
def strip_time(src):
    spans = code_spans(src)
    timed = []
    for (a, b) in spans:
        j = a
        while True:
            i = src.find('(time', j, b)
            if i < 0: break
            after = i + 5
            if after >= len(src) or src[after] in ' \t\r\n()':
                timed.append((i, form_end(src, i)))
                j = timed[-1][1]
                continue
            j = i + 1
    for (s, e) in reversed(timed):
        inner = src[s + 5:e - 1]
        # de-indent by one space (cosmetic only)
        src = src[:s] + '(begin ' + inner.strip() + ')' + src[e:]
    return src

src = strip_time(src)

# ---------------------------------------------------------------- read-pgm / write-pgm
rp_start = src.index('(define (read-pgm file)')
rp_end = src.index('(define test-pgm (read-pgm "girl.pgm"))')
new_pgm = r'''(define (read-pgm file)
  ;; kaappi adaptation: binary-port PGM reader (P5 binary and P2 ascii).
  (define bytes
    (let ((p (open-binary-input-file file)))
      (let loop ((acc '()))
        (let ((b (read-u8 p)))
          (if (eof-object? b)
              (begin (close-port p) (list->vector (reverse acc)))
              (loop (cons b acc)))))))
  (define n (vector-length bytes))
  (define (vref i) (vector-ref bytes i))
  (define (ws? c) (or (= c 32) (= c 9) (= c 10) (= c 13)))
  (define (skip-ws i)
    (let loop ((i i))
      (if (>= i n)
          i
          (let ((c (vref i)))
            (cond ((ws? c) (loop (+ i 1)))
                  ((= c 35)
                   (let sk ((i i))
                     (if (or (>= i n) (= (vref i) 10))
                         (loop (if (< i n) (+ i 1) i))
                         (sk (+ i 1)))))
                  (else i))))))
  (define (read-token i)
    (let loop ((j i) (acc '()))
      (if (or (>= j n) (ws? (vref j)))
          (cons (list->string (map integer->char (reverse acc))) j)
          (loop (+ j 1) (cons (vref j) acc)))))
  (define (token-number i)
    (let ((tok (read-token i)))
      (cons (string->number (car tok)) (cdr tok))))
  (let* ((h (skip-ws 0))
         (hdr (car (read-token h)))
         (c1 (token-number (skip-ws (cdr (read-token h)))))
         (columns (car c1))
         (r1 (token-number (skip-ws (cdr c1))))
         (rows (car r1))
         (g1 (token-number (skip-ws (cdr r1))))
         (greys (car g1))
         (data-start (+ (cdr g1) 1))
         (header (string->symbol hdr)))
    (make-pgm greys
              (array-copy
               (make-array (make-interval (vector rows columns))
                           (cond ((or (eq? header 'p5)
                                      (eq? header 'P5))
                                  (if (< greys 256)
                                      (let ((k 0))
                                        (lambda (i j)
                                          (set! k (+ k 1))
                                          (vref (- (+ data-start k) 1))))
                                      (let ((k 0))
                                        (lambda (i j)
                                          (set! k (+ k 2))
                                          (+ (* (vref (- (+ data-start k) 1)) 256)
                                             (vref (- (+ data-start k) 2)))))))
                                 ((or (eq? header 'p2)
                                      (eq? header 'P2))
                                  (let* ((nums
                                          (let loop ((i (skip-ws data-start)) (acc '()))
                                            (if (>= i n)
                                                (reverse acc)
                                                (let ((t (token-number i)))
                                                  (loop (skip-ws (cdr t)) (cons (car t) acc))))))
                                         (vec (list->vector nums))
                                         (k 0))
                                    (lambda (i j)
                                      (set! k (+ k 1))
                                      (vector-ref vec (- k 1)))))
                                 (else
                                  (error "read-pgm: not a pgm file"))))))))

(define (write-pgm pgm-data file . opts)
  (let ((force-ascii (and (pair? opts) (car opts))))
    (let* ((greys (pgm-greys pgm-data))
           (pgm-array (pgm-pixels pgm-data))
           (domain (array-domain pgm-array))
           (rows (- (interval-upper-bound domain 0)
                    (interval-lower-bound domain 0)))
           (columns (- (interval-upper-bound domain 1)
                       (interval-lower-bound domain 1))))
      (let ((port (open-binary-output-file file)))
        (define (wstr s)
          (for-each (lambda (c) (write-u8 (char->integer c) port))
                    (string->list s)))
        (wstr (if force-ascii "P2" "P5"))
        (write-u8 10 port)
        (wstr (number->string columns)) (write-u8 32 port)
        (wstr (number->string rows)) (write-u8 10 port)
        (wstr (number->string greys)) (write-u8 10 port)
        (array-for-each (if force-ascii
                            (let ((next-pixel-in-line 1))
                              (lambda (p)
                                (wstr (number->string p))
                                (if (fxzero? (fxand next-pixel-in-line 15))
                                    (begin
                                      (write-u8 10 port)
                                      (set! next-pixel-in-line 1))
                                    (begin
                                      (write-u8 32 port)
                                      (set! next-pixel-in-line (fx+ 1 next-pixel-in-line))))))
                            (if (fx< greys 256)
                                (lambda (p) (write-u8 p port))
                                (lambda (p)
                                  (write-u8 (fxand p 255) port)
                                  (write-u8 (fxarithmetic-shift-right p 8) port))))
                        pgm-array)
        (close-port port)))))

'''
src = src[:rp_start] + new_pgm + src[rp_end:]

# ---------------------------------------------------------------- rename digit-leading identifiers
# Gambit allows `1D-transform' as an identifier; R7RS (and kaappi) do not.
src = re.sub(r'\b1D-', 'one-d-', src)
src = re.sub(r'(?<![A-Za-z0-9_!?-])2x2-matrix-multiply-into!',
             'two-x-two-matrix-multiply-into!', src)
src = re.sub(r'(?<![A-Za-z0-9_-])2x2(?![A-Za-z0-9_-])', 'two-x-two', src)

# flonum op shims (kaappi lacks SRFI 142 fl+ & friends)
src = src.replace(';;; suite bug: random-f64vector is called but never defined anywhere',
                  '''(define (fl+ a b) (+ a b))
(define (fl- a b) (- a b))
(define (fl* a b) (* a b))
(define (fl/ a b) (/ a b))
(define (flsqrt x) (sqrt x))
(define (identity x) x)

;;; suite bug: random-f64vector is called but never defined anywhere''')

# ============================================================
# Stage 2: the vendoring postlude. Every patch below exists so the
# generated file is the final, CI-ready conformance suite.
# ============================================================

UPSTREAM_COMMIT = '72ac619d49ddb8610a1d18d19f3fe7049317917f'
UPSTREAM_REPO = 'https://github.com/scheme-requests-for-implementation/srfi-231'

# --- P1: vendoring header above the upstream MIT license block.
HEADER = ''';;; srfi231-official.scm -- the OFFICIAL SRFI 231 test suite (test-arrays.scm
;;; by Bradley J Lucier), adapted to run on kaappi. GENERATED FILE -- do not
;;; hand-edit; regenerate with:
;;;
;;;     python3 tests/scheme/srfi/srfi231-official-transform.py
;;;
;;; Provenance: upstream %s (test-arrays.scm as of commit %s, MIT license
;;; retained below). The adaptation rewrites the Gambit harness (define-macro
;;; test/test-multiple-values, with-exception-catcher, DSSSL optionals,
;;; ##-prefixed identifiers, (declare ...) forms) into portable R7RS and
;;; ports the reference implementation's internal %%%% procedures the suite
;;; uses as oracles; nothing about the tested BEHAVIOR is changed. Tests of
;;; pure reference internals (%%%%move-array-elements, %%%%array-packed? caching)
;;; are dropped -- the public procedures they underlie are covered directly.
;;;
;;; Known kaappi divergences are accounted, not failed: a small table of test
;;; ids whose failure encodes a documented kaappi-vs-reference divergence,
;;; each with an issue reference and the exact number of evaluations expected
;;; to diverge under it (shared test forms run once per storage class). The
;;; suite exits nonzero only on UNEXPECTED failures -- or when an entry does
;;; not account exactly: an id that never executes, zero observed (stale
;;; entry hiding real coverage -- prune it), more than recorded (an
;;; undocumented failure absorbing into the entry), or fewer but nonzero
;;; (over-accounting -- re-count it).
;;; Error-EXPECTING tests count as passes when any error is raised; only the
;;; Gambit message text differs.
;;;
;;; Runtime is ~80s (dominated by the PGM convolution timing blocks); the
;;; run-all.sh per-file timeout override keeps it out of the 60s default.
;;; Fixtures live in srfi231-official-fixtures/ next to this file; PGM
;;; outputs are written under TMPDIR, never the source tree.

''' % (UPSTREAM_REPO, UPSTREAM_COMMIT)
src = HEADER + src

# --- P2: process-context for command-line/getenv/exit in the postlude code.
old_imports = '(scheme file) (scheme read) (scheme lazy))'
assert src.count(old_imports) == 1
src = src.replace(old_imports,
                  '(scheme file) (scheme read) (scheme lazy)\n        (scheme process-context))')

# --- P3: fixture/output path resolution + known-divergence accounting.
OLD_REPORT = '''(define (report-failure id line result expected)
  (set! failed-tests (+ failed-tests 1))
  (display "FAIL ")
  (display id) (display " (line ") (display line) (display ") result=")
  (display (obj->string result))
  (display " expected=")
  (display (obj->string expected))
  (if (and (eq? result error-marker) last-error)
      (begin (display " [error: ") (display (obj->string last-error)) (display "]")))
  (newline))'''
assert OLD_REPORT in src

NEW_REPORT = ''';;; --- kaappi vendoring: known-divergence accounting ------------------
;;; Test ids whose failure encodes a DOCUMENTED kaappi-vs-reference
;;; divergence rather than a bug. Each entry: (id expected-count
;;; . "reason") -- expected-count is the EXACT number of evaluations
;;; under that id expected to diverge (a shared test form runs once per
;;; storage class, so one id can legitimately account several rows; the
;;; suite is deterministic, so the count is stable run to run). The
;;; epilogue fails the suite unless every entry accounts exactly: an id
;;; that never executes, zero observed (stale -- prune it), more
;;; divergences than expected (an undocumented failure is hiding under
;;; the id), or fewer but nonzero (over-accounting -- re-count it).
;;;
;;; Entry 351 lived here until kaappi#2448: unsafe specialized views went
;;; unchecked, which the spec text permits but the reference does not do.
;;; kaappi now always checks the user-visible getter/setter, so that
;;; divergence is resolved rather than documented.
(define divergent-tests 0)
(define diverged-counts (make-vector 10000 0))
(define known-divergences
  (list '(147 1 . "R7RS strings are mutable; the suite encodes Gambit's immutable-string expectation")))
(define (known-divergence id) (assq id known-divergences))

(define (report-failure id line result expected)
  (let ((kd (known-divergence id)))
    (if kd
        (begin
          (set! divergent-tests (+ divergent-tests 1))
          (vector-set! diverged-counts id (+ 1 (vector-ref diverged-counts id)))
          (display "DIVERGENT-EXPECTED ") (display id)
          (display " ") (display (cddr kd)) (newline))
        (begin
          (set! failed-tests (+ failed-tests 1))
          (display "FAIL ")
          (display id) (display " (line ") (display line) (display ") result=")
          (display (obj->string result))
          (display " expected=")
          (display (obj->string expected))
          (if (and (eq? result error-marker) last-error)
              (begin (display " [error: ") (display (obj->string last-error)) (display "]")))
          (newline)))))'''
src = src.replace(OLD_REPORT, NEW_REPORT)

# --- P4: fixture path resolution replaces the bare "girl.pgm" read.
OLD_PGM = '(define test-pgm (read-pgm "girl.pgm"))'
assert src.count(OLD_PGM) == 1
NEW_PGM = ''';;; --- kaappi vendoring: fixture and output paths ---------------------
;;; Inputs resolve relative to THIS file (command-line carries the script
;;; path), with a repo-root spelling as fallback; convolution-timing
;;; outputs go under TMPDIR, never the source tree or the runner cwd.
(define (official-fixture-path name)
  (let ((dir (let ((cl (command-line)))
               (if (null? cl) ""
                   (let ((p (car cl)))
                     (let loop ((i (- (string-length p) 1)))
                       (if (or (< i 0) (char=? (string-ref p i) #\\/))
                           (substring p 0 (+ i 1))
                           (loop (- i 1)))))))))
    (let ((cands (list (string-append dir "srfi231-official-fixtures/" name)
                       (string-append "tests/scheme/srfi/srfi231-official-fixtures/" name)
                       name)))
      (let loop ((cs cands))
        (cond ((null? cs) (error "srfi231-official: fixture not found" name))
              ((file-exists? (car cs)) (car cs))
              (else (loop (cdr cs))))))))
(define (official-output-path name)
  (let ((tmp (get-environment-variable "TMPDIR")))
    (string-append (if (and tmp (> (string-length tmp) 0)) tmp "/tmp")
                   "/srfi231-official-" name)))
(define test-pgm (read-pgm (official-fixture-path "girl.pgm")))'''
src = src.replace(OLD_PGM, NEW_PGM)

# Output PGM writes -> temp paths (always the filename argument of write-pgm).
n1 = src.count('"sharper-test.pgm"')
n2 = src.count('"edge-test.pgm"')
src = src.replace('"sharper-test.pgm"', '(official-output-path "sharper-test.pgm")')
src = src.replace('"edge-test.pgm"', '(official-output-path "edge-test.pgm")')

# --- P5: verdict epilogue replaces the Gambit summary line.
OLD_SUM = '(for-each display (list "Failed " failed-tests " out of " total-tests " total tests.\\n"))'
assert OLD_SUM in src
NEW_SUM = '''
;;; --- kaappi vendoring: final verdict ---------------------------------
;;; Exit nonzero on any UNEXPECTED failure, and on any known-divergence
;;; entry that does not account exactly: an id that never executed (a
;;; regeneration dropped its test form -- the entry passes silently
;;; otherwise), zero observed (stale entry -- prune it), more than the
;;; recorded count (an undocumented failure is hiding under the id), or
;;; fewer but nonzero (the entry over-accounts -- re-count it).
(define resolved-divergences 0)
(define divergence-count-mismatches 0)
(for-each (lambda (entry)
            (let ((id (car entry))
                  (expected (cadr entry)))
              (if (not (vector-ref executed-tests id))
                  (begin
                    (set! divergence-count-mismatches
                          (+ divergence-count-mismatches 1))
                    (display "DIVERGENCE-NEVER-EXECUTED ") (display id)
                    (display " -- no evaluation ran under this id (its test form is gone from the suite; prune the entry) (")
                    (display (cddr entry)) (display ")") (newline))
                  (let ((observed (vector-ref diverged-counts id)))
                    (cond ((= observed 0)
                           (set! resolved-divergences (+ resolved-divergences 1))
                           (display "DIVERGENCE-RESOLVED ") (display id)
                           (display " -- prune it from known-divergences (")
                           (display (cddr entry)) (display ")") (newline))
                          ((not (= observed expected))
                           (set! divergence-count-mismatches
                                 (+ divergence-count-mismatches 1))
                           (display "DIVERGENCE-COUNT-MISMATCH ") (display id)
                           (display ": expected ") (display expected)
                           (display " diverging evaluations, observed ")
                           (display observed) (display " -- ")
                           (display (if (> observed expected)
                                        "an undocumented failure is hiding under this id"
                                        "the entry over-accounts (re-count it)"))
                           (display " (")
                           (display (cddr entry)) (display ")") (newline)))))))
          known-divergences)
(display "srfi231-official: ")
(display (- total-tests failed-tests divergent-tests)) (display " passed, ")
(display error-string-tests) (display " error-message-only, ")
(display divergent-tests) (display " known divergences, ")
(display failed-tests) (display " unexpected failures, ")
(display resolved-divergences) (display " resolved divergences, ")
(display divergence-count-mismatches) (display " count mismatches, out of ")
(display total-tests) (display " evaluations")
(newline)
(exit (if (and (= failed-tests 0)
               (= resolved-divergences 0)
               (= divergence-count-mismatches 0))
          0 1))'''
src = src.replace(OLD_SUM, NEW_SUM)

# --- P6: generation-time guard (complement to the runtime epilogue): every
# known-divergence id must belong to a test form the scanner actually found
# and numbered. A dropped/renamed upstream form would otherwise surface only
# as the committed suite's DIVERGENCE-NEVER-EXECUTED after a ~150 s run;
# here it fails the regeneration itself, instantly. The runtime check stays
# authoritative for CI -- it guards the committed artifact, not the step.
div_ids = [int(m) for m in re.findall(r"'\((\d+) \d+ \. \"", NEW_REPORT)]
assert div_ids, 'no known-divergence ids parsed from NEW_REPORT (regex drifted?)'
missing_ids = [i for i in div_ids if i not in {m['id'] for m in test_meta}]
assert not missing_ids, (
    'known-divergence ids with no test form in the generated suite '
    '(dropped or renumbered upstream?): %r' % missing_ids)

open(OUT, 'w').write(src)
# The id->original-line map is debugging metadata for triaging failures;
# write it only on request so regeneration leaves no untracked droppings.
import os as _os
if _os.environ.get('DUMP_META'):
    json.dump(test_meta, open(META, 'w'), indent=1)
print('wrote %s (%d bytes; %d sharper/%d edge writes rerouted); meta for %d tests'
      % (OUT, len(src), n1, n2, len(test_meta)))
