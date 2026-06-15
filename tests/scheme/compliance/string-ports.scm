;;; String port compliance tests (R7RS 6.13)

;; open-input-string / read-char
(let ((p (open-input-string "hello")))
  (display (read-char p))    ; => h
  (display (read-char p))    ; => e
  (display (read-char p))    ; => l
  (newline))

;; open-output-string / get-output-string
(let ((p (open-output-string)))
  (write-char #\H p)
  (write-string "ello" p)
  (display (get-output-string p)))  ; => Hello
(newline)

;; read-line from string port
(let ((p (open-input-string "line1\nline2\n")))
  (display (read-line p))  ; => line1
  (newline)
  (display (read-line p))  ; => line2
  (newline))

;; read from string port
(let ((p (open-input-string "(+ 1 2)")))
  (let ((datum (read p)))
    (display datum)))  ; => (+ 1 2)
(newline)

;; peek-char from string port
(let ((p (open-input-string "ab")))
  (display (peek-char p))   ; => a  (doesn't consume)
  (display (read-char p))   ; => a  (now consumes)
  (display (read-char p)))  ; => b
(newline)

;; read-string
(let ((p (open-input-string "hello world")))
  (display (read-string 5 p)))  ; => hello
(newline)

;; eof on empty string port
(let ((p (open-input-string "")))
  (display (eof-object? (read-char p))))  ; => #t
(newline)

;; flush-output-port (should be no-op, no error)
(flush-output-port)

;; port predicates on string ports
(let ((ip (open-input-string "test"))
      (op (open-output-string)))
  (display (port? ip))         ; => #t
  (display (input-port? ip))   ; => #t
  (display (output-port? op))  ; => #t
  (newline))
