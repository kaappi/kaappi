;;; SRFI 203 — A Simple Picture Language in the Style of SICP
;;;
;;; The spec itself is deliberately minimal: canvas lifecycle, draw-line,
;;; a fixed "rogers" painter, and image-file painters — the higher-level
;;; SICP combinators (beside, above, flip-vert, rotate90, ...) are NOT part
;;; of this SRFI; user/book code is expected to define them in terms of
;;; frames and these primitives, exactly as SICP itself does.
;;;
;;; Kaappi has no window system and no image codec, so "canvas" is
;;; implemented as an in-memory list of SVG elements that canvas-refresh
;;; writes out as an actual "canvas.svg" file — one of the spec's own
;;; explicitly sanctioned strategies ("could be a window, or a file, or
;;; some other drawing device"; canvas-refresh "returns an
;;; implementation-defined identifier... could be a filename"). A frame
;;; (origin edge1 edge2) is exactly an affine basis, which maps directly
;;; onto SVG's `matrix(a,b,c,d,e,f)` transform — so jpeg-file->painter/
;;; image-file->painter reference the original image file directly via an
;;; SVG <image> element with that transform, rather than decoding pixels
;;; Kaappi has no codec for; any SVG viewer (a browser) then does the
;;; actual warping. y is flipped on output (canvas-size - y*canvas-size)
;;; since SVG grows downward but SICP's frame convention grows upward.
;;;
;;; `rogers` does NOT reproduce the real SICP figure 2.11 line data (that
;;; specific hand-digitized portrait isn't published anywhere this port
;;; could source it from) — it's a placeholder line-drawing (a simple
;;; stylized face) satisfying the same contract: a fixed painter, callable
;;; on any frame, producing a different (correctly warped) result per
;;; frame. Documented here rather than silently passed off as the real
;;; image.

(define-library (srfi 203)
  (import (scheme base) (scheme cxr) (scheme file) (scheme write))
  (export canvas-reset canvas-refresh canvas-cleanup
          draw-line rogers jpeg-file->painter image-file->painter)
  (begin

    (define %canvas-size 400)
    (define %canvas-elements '())  ; reverse order

    (define (canvas-reset)
      (set! %canvas-elements '())
      (if #f #f))

    (define (%emit! element-string)
      (set! %canvas-elements (cons element-string %canvas-elements)))

    ;; SVG y grows downward; frame/vector coordinates follow SICP's
    ;; upward-growing convention.
    (define (%px x) (* x %canvas-size))
    (define (%py y) (- %canvas-size (* y %canvas-size)))

    (define (draw-line start end)
      (%emit!
        (string-append
          "<line x1=\"" (number->string (%px (car start)))
          "\" y1=\"" (number->string (%py (cadr start)))
          "\" x2=\"" (number->string (%px (car end)))
          "\" y2=\"" (number->string (%py (cadr end)))
          "\" stroke=\"black\" stroke-width=\"1\"/>")))

    (define (canvas-refresh)
      (let ((filename "canvas.svg"))
        (call-with-output-file filename
          (lambda (port)
            (display "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" port)
            (display (string-append
                       "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\""
                       (number->string %canvas-size) "\" height=\""
                       (number->string %canvas-size) "\">\n")
                     port)
            (display (string-append
                       "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>\n")
                     port)
            (for-each (lambda (el) (display el port) (newline port))
                      (reverse %canvas-elements))
            (display "</svg>\n" port)))
        filename))

    (define (canvas-cleanup)
      (set! %canvas-elements '())
      (if #f #f))

    ;; --- frames --------------------------------------------------------
    ;; A frame is (origin edge1 edge2), each a vector-list (x y . extra).
    ;; Maps unit-square coordinates (x, y) to canvas coordinates:
    ;;   origin + x*edge1 + y*edge2

    (define (%vx v) (car v))
    (define (%vy v) (cadr v))

    (define (%frame-map frame x y)
      (let* ((origin (car frame)) (edge1 (cadr frame)) (edge2 (caddr frame)))
        (list (+ (%vx origin) (* x (%vx edge1)) (* y (%vx edge2)))
              (+ (%vy origin) (* x (%vy edge1)) (* y (%vy edge2))))))

    (define (%draw-segments-in-frame frame segments)
      (for-each
        (lambda (seg)
          (draw-line (%frame-map frame (car seg) (cadr seg))
                     (%frame-map frame (caddr seg) (cadddr seg))))
        segments))

    ;; Placeholder line data (unit square, origin bottom-left) — see file
    ;; header. A simple stylized face: outline, two eyes, a smile.
    (define %rogers-segments
      '((0.5 0.95 0.15 0.6)   (0.15 0.6 0.15 0.25)  (0.15 0.25 0.5 0.05)
        (0.5 0.05 0.85 0.25)  (0.85 0.25 0.85 0.6)  (0.85 0.6 0.5 0.95)
        (0.3 0.65 0.4 0.65)   (0.6 0.65 0.7 0.65)
        (0.35 0.35 0.65 0.35) (0.4 0.3 0.6 0.3) (0.4 0.3 0.4 0.35) (0.6 0.3 0.6 0.35)))

    (define (rogers frame)
      (%draw-segments-in-frame frame %rogers-segments))

    ;; --- image-file painters --------------------------------------------

    ;; SVG's <image> occupies the unit square (0,0)-(1,1) in its own local
    ;; coordinates and is placed by matrix(a,b,c,d,e,f), which maps a local
    ;; point (u,v) to (a*u + c*v + e, b*u + d*v + f) in canvas pixel space.
    ;; We want that to land exactly where %frame-map + %px/%py would put
    ;; the unit-square point (u,v): expanding %px/%py over %frame-map's
    ;; origin + u*edge1 + v*edge2 and matching coefficients gives a/c from
    ;; edge1/edge2's x components scaled by %px, b/d from their y
    ;; components scaled and sign-flipped (the canvas-height offset that
    ;; %py adds for a point cancels out for a direction), and e/f from
    ;; %px/%py applied to the origin point itself.
    (define (%make-image-painter file-name)
      (lambda (frame)
        (let* ((origin (car frame)) (edge1 (cadr frame)) (edge2 (caddr frame))
               (a (%px (%vx edge1))) (b (- (%px (%vy edge1))))
               (c (%px (%vx edge2))) (d (- (%px (%vy edge2))))
               (e (%px (%vx origin))) (f (%py (%vy origin))))
          (%emit!
            (string-append
              "<image href=\"" file-name "\" width=\"1\" height=\"1\" "
              "transform=\"matrix("
              (number->string a) "," (number->string b) ","
              (number->string c) "," (number->string d) ","
              (number->string e) "," (number->string f) ")\"/>")))))

    (define (jpeg-file->painter file-name) (%make-image-painter file-name))
    (define (image-file->painter file-name) (%make-image-painter file-name))))
