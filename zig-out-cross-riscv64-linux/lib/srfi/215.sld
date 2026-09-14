;;; SRFI 215 — Central Log Exchange
;;;
;;; One procedure, two parameters, eight severity constants: send-log
;;; constructs a log message (a plain association list, not a record
;;; type) from a severity, a human-readable message, an optional flat
;;; list of key/value fields, and whatever (current-log-fields)
;;; contributes on top -- then hands that alist to whatever procedure
;;; (current-log-callback) currently holds. Both are ordinary R7RS
;;; parameter objects, installed exactly like current-output-port:
;;; `parameterize` for a dynamic extent (e.g. a test runner capturing
;;; messages), or calling the parameter procedure with one argument to
;;; replace it outright. There is no separate register/unregister API,
;;; no built-in fan-out to multiple receivers, and no built-in
;;; severity-based filtering -- the spec makes all of that the
;;; installed callback's own responsibility.
;;;
;;; A constructed log message always starts with the mandatory SEVERITY
;;; and MESSAGE keys (stored exactly as given -- the spec never
;;; describes a conversion step for either), followed by the key/value
;;; pairs passed directly to send-log, followed by the pairs from
;;; (current-log-fields) -- per the spec, the explicit arguments take
;;; precedence in position over the ambient fields. Every other field
;;; value is converted to a string via `write` unless it already
;;; satisfies string?, bytevector?, or exact-integer?, or is an
;;; error-object? (R7RS) -- the spec also exempts R6RS condition?
;;; values, but Kaappi has no R6RS condition system, so that predicate
;;; is simply omitted here.
;;;
;;; Before any real callback is installed, the default
;;; current-log-callback buffers messages -- the spec permits "an
;;; implementation-defined number" and says nothing about overflow
;;; behavior, so this implementation caps the buffer and drops the
;;; oldest messages once it's full, rather than growing without limit.
;;; Replacing the callback -- via `parameterize` or a direct call --
;;; flushes anything buffered into the incoming callback first, oldest
;;; message first, via the parameter's converter procedure, looping
;;; until nothing remains so a message the incoming callback itself logs
;;; reentrantly during the flush is delivered too rather than stranded.
;;; That converter runs exactly once per replacement and never on
;;; `parameterize`'s automatic restore (Kaappi's parameterize desugaring
;;; saves/restores the already-converted old value directly, without
;;; re-invoking the converter), so restoring a previous callback on the
;;; way out of a dynamic extent can never re-trigger a flush. The
;;; converter also rejects a non-procedure replacement before touching
;;; the buffer, so an invalid `(current-log-callback ...)` call leaves
;;; anything already buffered recoverable by a later, valid install.
;;;
;;; send-log does not skip constructing a message when no receiver
;;; wants that severity -- the spec describes no such laziness. A
;;; callback that only cares about, say, warnings and worse is expected
;;; to check (cdr (assq 'SEVERITY msg)) itself and discard the rest.

(define-library (srfi 215)
  (export send-log
          current-log-fields
          current-log-callback
          EMERGENCY
          ALERT
          CRITICAL
          ERROR
          WARNING
          NOTICE
          INFO
          DEBUG)
  (import (scheme base) (scheme write))
  (begin

    ;; Severity constants, per the spec's table -- 0 is the most severe,
    ;; 7 the least, matching RFC 5424 / the systemd journal.
    (define EMERGENCY 0)
    (define ALERT 1)
    (define CRITICAL 2)
    (define ERROR 3)
    (define WARNING 4)
    (define NOTICE 5)
    (define INFO 6)
    (define DEBUG 7)

    ;; A flat plist of additional keys/values automatically appended to
    ;; every message's fields. Default: none.
    (define current-log-fields (make-parameter '()))

    ;; Converts a field value into one of the types a log callback can
    ;; always safely serialize, per the spec's "Log messages" section.
    (define (%log-field-value v)
      (if (or (string? v) (bytevector? v) (exact-integer? v) (error-object? v))
          v
          (let ((out (open-output-string)))
            (write v out)
            (get-output-string out))))

    ;; Walks a flat plist of alternating keys/values -- the shape of
    ;; both send-log's own trailing arguments and current-log-fields --
    ;; into a list of (key . converted-value) pairs, preserving order.
    ;; Signals an error for an odd-length plist or a non-symbol key, as
    ;; the spec requires of send-log's own arguments.
    (define (%plist->fields plist who)
      (let loop ((lst plist) (acc '()))
        (cond ((null? lst) (reverse acc))
              ((not (pair? lst)) (error (string-append who
                                                       ": improper key/value list")
                                        plist))
              ((null? (cdr lst)) (error (string-append who
                                                       ": odd number of key/value arguments")
                                        plist))
              ((not (symbol? (car lst))) (error (string-append who
                                                               ": key is not a symbol")
                                                (car lst)))
              (else (loop (cddr lst)
                          (cons (cons (car lst) (%log-field-value (cadr lst)))
                                acc))))))

    ;; Messages sent while the default callback (below) is current, held
    ;; newest-first so buffering is a plain cons; flushing reverses once.
    ;; Bounded by %max-buffered-messages so a program that never installs
    ;; a real callback (e.g. a long-running server whose only SRFI-215
    ;; user is a dependency that logs routinely) can't leak memory
    ;; without limit -- the spec permits any "implementation-defined
    ;; number" and says nothing about overflow behavior, so once the cap
    ;; is hit the oldest half is dropped at once, keeping eviction cost
    ;; O(1) amortized instead of O(cap) on every call past the cap.
    (define %max-buffered-messages 1000)
    (define %buffered-messages '())
    (define %buffered-message-count 0)

    ;; The default value of current-log-callback: buffers every message
    ;; it's given, up to %max-buffered-messages, until replaced.
    (define (%buffering-callback msg)
      (set! %buffered-messages (cons msg %buffered-messages))
      (set! %buffered-message-count (+ %buffered-message-count 1))
      (when (> %buffered-message-count %max-buffered-messages)
        (let ((keep (quotient %max-buffered-messages 2)))
          (set! %buffered-messages (%take %buffered-messages keep))
          (set! %buffered-message-count keep))))

    ;; Keeps the first n elements of lst (n <= (length lst)).
    (define (%take lst n)
      (if (or (= n 0) (null? lst))
          '()
          (cons (car lst) (%take (cdr lst) (- n 1)))))

    ;; current-log-callback's converter. Runs once whenever the callback
    ;; is replaced (parameterize entry or a direct call). Validates proc
    ;; first, before touching the buffer, so an invalid replacement
    ;; leaves already-buffered messages recoverable by a later, valid
    ;; install rather than discarding them. Then drains anything
    ;; buffered by %buffering-callback into proc, oldest first, looping
    ;; until the buffer is dry rather than stopping after one pass: proc
    ;; runs here, before the parameter's value actually becomes proc
    ;; (that happens only once this converter returns), so a message
    ;; proc sends reentrantly via send-log during the flush lands back
    ;; in %buffered-messages instead of reaching proc directly. Looping
    ;; catches that and delivers it within this same operation instead
    ;; of stranding it until some later, unrelated callback replacement.
    (define (%install-log-callback proc)
      (unless (procedure? proc)
        (error "current-log-callback: not a procedure" proc))
      (let flush ()
        (unless (null? %buffered-messages)
          (let ((pending (reverse %buffered-messages)))
            (set! %buffered-messages '())
            (set! %buffered-message-count 0)
            (for-each proc pending)
            (flush))))
      proc)

    ;; The current log receiver. Analogous to current-output-port: a
    ;; single dynamically-scoped slot, no register/unregister list.
    (define current-log-callback
      (make-parameter %buffering-callback %install-log-callback))

    (define (send-log severity message . plist)
      ((current-log-callback) (append (list (cons 'SEVERITY severity)
                                            (cons 'MESSAGE message))
                                      (%plist->fields plist "send-log")
                                      (%plist->fields (current-log-fields)
                                                      "current-log-fields"))))))
