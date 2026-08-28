;; SRFI 274: Extended List Conversion Procedures.
;;
;; The bare (srfi 274) name is an alias for the base sub-library: it exports
;; the three extended conversions that shadow (scheme base) bindings
;; (list-copy, list->string, list->vector). The collection-specific extended
;; conversions live in their own sub-libraries — (srfi 274 41),
;; (srfi 274 134), (srfi 274 158), (srfi 274 160 base) and the twelve
;; (srfi 274 160 <type>) — so importing them never has to displace the
;; built-ins a program already uses. The SRFI's own tests import
;; (srfi 274 base) with (except (scheme base) ...) for the same reason.
(define-library (srfi 274)
  (import (srfi 274 base))
  (export list-copy list->string list->vector))
