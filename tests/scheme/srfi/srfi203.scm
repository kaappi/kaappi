;; SRFI-203 (A Simple Picture Language in the Style of SICP) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi203.scm
;;
;; Kaappi has no window system or image codec; this SRFI's "canvas" is
;; implemented as an in-memory SVG document (see lib/srfi/203.sld header).
;; These tests inspect the SVG text directly rather than pixels.

(import (scheme base) (scheme file) (scheme process-context) (srfi 203) (srfi 64))

(test-begin "srfi-203")

(define (%slurp filename)
  (call-with-input-file filename
    (lambda (port)
      (let loop ((acc '()))
        (let ((c (read-char port)))
          (if (eof-object? c)
              (list->string (reverse acc))
              (loop (cons c acc))))))))

(define (%count-occurrences haystack needle)
  (let ((hlen (string-length haystack)) (nlen (string-length needle)))
    (let loop ((i 0) (n 0))
      (cond ((> (+ i nlen) hlen) n)
            ((string=? (substring haystack i (+ i nlen)) needle) (loop (+ i nlen) (+ n 1)))
            (else (loop (+ i 1) n))))))

(define (%contains? haystack needle) (> (%count-occurrences haystack needle) 0))

;;; --- canvas lifecycle + draw-line + canvas-refresh ---
(canvas-reset)
(draw-line '(0 0) '(1 1))
(let ((filename (canvas-refresh)))
  (test-equal "canvas-refresh: returns filename" "canvas.svg" filename)
  (test-assert "canvas-refresh: file exists" (file-exists? filename))
  (let ((contents (%slurp filename)))
    (test-assert "canvas-refresh: XML declaration" (%contains? contents "<?xml"))
    (test-assert "canvas-refresh: svg element" (%contains? contents "<svg"))
    (test-assert "canvas-refresh: closes svg element" (%contains? contents "</svg>"))
    ;; unit-square (0,0)-(1,1) on a 400x400 canvas, y flipped: (0,400)-(400,0)
    (test-assert "draw-line: maps (0,0)-(1,1) to canvas corners"
      (%contains? contents "<line x1=\"0\" y1=\"400\" x2=\"400\" y2=\"0\""))))

;;; --- canvas-cleanup actually clears prior elements ---
(canvas-cleanup)
(draw-line '(0 0) '(0 0))
(let* ((filename (canvas-refresh)) (contents (%slurp filename)))
  (test-equal "canvas-cleanup: only the new draw remains"
    1 (%count-occurrences contents "<line")))

;;; --- rogers: fixed painter, callable on different frames without error ---
(canvas-reset)
(rogers (list '(0 0) '(1 0) '(0 1)))
(let* ((filename (canvas-refresh)) (contents (%slurp filename)))
  (test-equal "rogers: draws all 12 placeholder segments"
    12 (%count-occurrences contents "<line")))

(canvas-reset)
(rogers (list '(1/4 1/4) '(1/2 0) '(0 1/2)))
(let* ((filename (canvas-refresh)) (contents (%slurp filename)))
  (test-equal "rogers: works on a different (smaller, offset) frame too"
    12 (%count-occurrences contents "<line")))

;;; --- image-file painters ---
(test-assert "jpeg-file->painter: returns a procedure" (procedure? (jpeg-file->painter "photo.jpg")))
(test-assert "image-file->painter: returns a procedure" (procedure? (image-file->painter "photo.png")))

(canvas-reset)
((image-file->painter "photo.png") (list '(1/4 1/4) '(1/2 0) '(0 1/2)))
(let* ((filename (canvas-refresh)) (contents (%slurp filename)))
  (test-assert "image-file->painter: references the file" (%contains? contents "photo.png"))
  ;; frame (origin (1/4 1/4) edge1 (1/2 0) edge2 (0 1/2)) on a 400x400 canvas:
  ;; a=%px(1/2)=200, b=-%px(0)=0, c=%px(0)=0, d=-%px(1/2)=-200,
  ;; e=%px(1/4)=100, f=%py(1/4)=300
  (test-assert "image-file->painter: emits the frame's affine matrix"
    (%contains? contents "matrix(200,0,0,-200,100,300)")))

(delete-file "canvas.svg")

(let ((runner (test-runner-current)))
  (test-end "srfi-203")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
