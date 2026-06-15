;;; Process-context library compliance tests (R7RS 6.14)

;; command-line returns a list
(display (list? (command-line)))  ; => #t
(newline)

;; get-environment-variable for known var
(display (string? (get-environment-variable "HOME")))  ; => #t
(newline)

;; get-environment-variable for unknown var returns #f
(display (get-environment-variable "KAAPPI_NONEXISTENT_VAR_12345"))  ; => #f
(newline)

;; get-environment-variables returns a list
(display (list? (get-environment-variables)))  ; => #t
(newline)
