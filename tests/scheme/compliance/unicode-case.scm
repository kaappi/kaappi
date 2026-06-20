;; Comprehensive Unicode case mapping tests
;; Tests scripts beyond basic Latin/Greek/Cyrillic
(import (scheme base) (scheme char) (scheme write))

(define pass 0)
(define fail 0)
(define (check name expected actual)
  (if (equal? expected actual)
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: ") (display name)
      (display " expected=") (write expected)
      (display " got=") (write actual)
      (newline))))

;; --- Basic Latin (sanity) ---
(check "upcase a" #\A (char-upcase #\a))
(check "downcase A" #\a (char-downcase #\A))
(check "upcase z" #\Z (char-upcase #\z))

;; --- Latin-1 Supplement ---
(check "upcase ä" #\Ä (char-upcase #\ä))
(check "downcase Ö" #\ö (char-downcase #\Ö))
(check "upcase ü" #\Ü (char-upcase #\ü))
(check "upper? Ñ" #t (char-upper-case? #\Ñ))
(check "lower? ñ" #t (char-lower-case? #\ñ))

;; --- Latin Extended-A ---
(check "upcase ā" #\Ā (char-upcase #\ā))      ; 0x101 -> 0x100
(check "downcase Ā" #\ā (char-downcase #\Ā))   ; 0x100 -> 0x101
(check "upcase ő" #\Ő (char-upcase #\ő))      ; 0x151 -> 0x150
(check "downcase Ő" #\ő (char-downcase #\Ő))   ; 0x150 -> 0x151

;; --- Latin Extended-B ---
(check "upcase ƀ" #\Ƀ (char-upcase #\ƀ))      ; 0x180 -> 0x243
(check "downcase Ɓ" #\ɓ (char-downcase #\Ɓ))   ; 0x181 -> 0x253
(check "downcase Ƃ" #\ƃ (char-downcase #\Ƃ))   ; 0x182 -> 0x183

;; --- Latin Extended Additional (Vietnamese, etc.) ---
(check "upcase ạ" #\Ạ (char-upcase #\ạ))      ; 0x1EA1 -> 0x1EA0
(check "downcase Ạ" #\ạ (char-downcase #\Ạ))   ; 0x1EA0 -> 0x1EA1
(check "upcase ề" #\Ề (char-upcase #\ề))      ; 0x1EC1 -> 0x1EC0
(check "downcase Ẃ" #\ẃ (char-downcase #\Ẃ))   ; 0x1E82 -> 0x1E83

;; --- Greek Extended (polytonic) ---
(check "upcase ἀ" #\Ἀ (char-upcase #\ἀ))      ; 0x1F00 -> 0x1F08
(check "downcase Ἀ" #\ἀ (char-downcase #\Ἀ))   ; 0x1F08 -> 0x1F00
(check "upper? Ἐ" #t (char-upper-case? #\Ἐ))    ; 0x1F18

;; --- Greek accented ---
(check "upcase ά" #\Ά (char-upcase #\ά))      ; 0x03AC -> 0x0386
(check "downcase Ά" #\ά (char-downcase #\Ά))   ; 0x0386 -> 0x03AC
(check "upcase ω" #\Ω (char-upcase #\ω))      ; 0x03C9 -> 0x03A9
(check "downcase Σ" #\σ (char-downcase #\Σ))   ; 0x03A3 -> 0x03C3

;; --- Cyrillic ---
(check "upcase а" #\А (char-upcase #\а))      ; 0x430 -> 0x410
(check "downcase Я" #\я (char-downcase #\Я))   ; 0x42F -> 0x44F
(check "upper? Д" #t (char-upper-case? #\Д))

;; --- Cyrillic Extended ---
(check "upcase ӂ" #\Ӂ (char-upcase #\ӂ))      ; 0x04C2 -> 0x04C1
(check "downcase Ӂ" #\ӂ (char-downcase #\Ӂ))   ; 0x04C1 -> 0x04C2
(check "upcase ё" #\Ё (char-upcase #\ё))      ; 0x0451 -> 0x0401
(check "downcase Ё" #\ё (char-downcase #\Ё))   ; 0x0401 -> 0x0451

;; --- Armenian ---
(check "upcase ա" #\Ա (char-upcase #\ա))      ; 0x561 -> 0x531
(check "downcase Ա" #\ա (char-downcase #\Ա))   ; 0x531 -> 0x561

;; --- Georgian ---
(check "upcase ა" #\Ა (char-upcase #\ა))      ; 0x10D0 -> 0x1C90

;; --- Cherokee ---
(check "lower? ꭰ" #t (char-lower-case? #\ꭰ))   ; 0xAB70

;; --- Deseret (SMP) ---
(check "upcase 𐐨" #\𐐀 (char-upcase #\𐐨))     ; 0x10428 -> 0x10400
(check "downcase 𐐀" #\𐐨 (char-downcase #\𐐀))  ; 0x10400 -> 0x10428
(check "upper? 𐐀" #t (char-upper-case? #\𐐀))    ; 0x10400
(check "lower? 𐐨" #t (char-lower-case? #\𐐨))    ; 0x10428

;; --- Osage (SMP) ---
(check "downcase 𐓀" #\𐓨 (char-downcase #\𐓀))  ; 0x104C0 -> 0x104E8
(check "upcase 𐓨" #\𐓀 (char-upcase #\𐓨))     ; 0x104E8 -> 0x104C0

;; --- Adlam (SMP) ---
(check "downcase 𞤀" #\𞤢 (char-downcase #\𞤀))  ; 0x1E900 -> 0x1E922
(check "upcase 𞤢" #\𞤀 (char-upcase #\𞤢))     ; 0x1E922 -> 0x1E900

;; --- Coptic ---
(check "upcase ⲁ" #\Ⲁ (char-upcase #\ⲁ))     ; 0x2C81 -> 0x2C80
(check "downcase Ⲁ" #\ⲁ (char-downcase #\Ⲁ))  ; 0x2C80 -> 0x2C81

;; --- Glagolitic ---
(check "downcase Ⰰ" #\ⰰ (char-downcase #\Ⰰ))  ; 0x2C00 -> 0x2C30
(check "upcase ⰰ" #\Ⰰ (char-upcase #\ⰰ))     ; 0x2C30 -> 0x2C00

;; --- Case folding (char-foldcase) ---
(check "foldcase A" #\a (char-foldcase #\A))
(check "foldcase Σ" #\σ (char-foldcase #\Σ))
(check "foldcase long-s" #\s (char-foldcase #\ſ))  ; 0x017F -> s
(check "foldcase micro" #\μ (char-foldcase #\µ))   ; 0x00B5 -> 0x03BC

;; --- String case operations ---
(check "string-upcase vietnamese"
  "ẠẢẤ" (string-upcase "ạảấ"))
(check "string-downcase cyrillic-ext"
  "ёӂ" (string-downcase "ЁӁ"))
(check "string-upcase deseret"
  "𐐀𐐁𐐂" (string-upcase "𐐨𐐩𐐪"))
(check "string-foldcase mixed"
  "aбα" (string-foldcase "AБΑ"))

;; --- char-ci=? with folding ---
(check "ci= micro/mu" #t (char-ci=? #\µ #\μ))
(check "ci= long-s/s" #t (char-ci=? #\ſ #\s))

;; --- Boundary: non-cased characters unchanged ---
(check "upcase digit" #\5 (char-upcase #\5))
(check "downcase space" #\space (char-downcase #\space))
(check "upper? 中" #f (char-upper-case? #\中))
(check "lower? 中" #f (char-lower-case? #\中))

(display pass) (display " pass, ")
(display fail) (display " fail")
(newline)
(if (> fail 0) (exit 1))
