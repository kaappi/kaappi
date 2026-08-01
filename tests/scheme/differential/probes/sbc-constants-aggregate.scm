;; Probe: text and aggregate constant tags survive a `.sbc` round trip.
;;
;; Audit v2, Phase 4E.  Companion to sbc-constants-numeric.scm; see that file's
;; header for the oracle and for why nothing here may `import`.
;;
;; Two tags in `writeConstant` are deliberately NOT probed here:
;;
;;   - an *uninterned* symbol (SRFI 258).  `TAG_SYMBOL` writes only the name
;;     and `readConstant` calls `gc.allocSymbol`, which interns — so a round
;;     trip would silently intern it.  It is unreachable in practice: the only
;;     constructors are `string->uninterned-symbol` /
;;     `generate-uninterned-symbol`, which run at run time and produce values
;;     that never enter a constant pool, and reaching them at all needs
;;     `(import (srfi 258))`, which makes the file uncacheable anyway.
;;   - `TAG_FUNCTION`, exercised by sbc-closures.scm rather than here.

(define (chk name a b)
  (display name)
  (display " ")
  (display (if (equal? a b) "ok" (list "MISMATCH" a b)))
  (newline))

;; --- strings: UTF-8 bytes are copied verbatim, so non-ASCII matters -------
(write (list "" "ascii" "λ αβγ 日本語" "tab\there" "q\"q" "b\\b"))
(newline)
(chk "string-length-codepoints" (list (string-length "λαβ")) (list 3))
(chk "string-value" '"λx" (string (integer->char #x3bb) #\x))

;; --- characters, including the top of the code-point range ---------------
(write (list #\a #\space #\newline #\tab #\x41 #\x03bb #\x10FFFF #\null #\delete))
(newline)
(chk "char-high" '#\x10FFFF (integer->char #x10FFFF))
(chk "char-codepoints" (list (char->integer #\x03bb) (char->integer #\null)) (list #x3bb 0))

;; --- symbols, including the ones needing |...| on the way back out -------
(write (list 'plain '|weird sym| '|| 'UPPER 'a.b 'λμ))
(newline)
(chk "symbol-value" 'abc (string->symbol "abc"))
(chk "symbol-eq" (list (eq? '|weird sym| (string->symbol "weird sym"))) (list #t))

;; --- bytevectors ----------------------------------------------------------
(write (list #u8() #u8(0 1 255) #u8(128 64 32)))
(newline)
(chk "bytevector-value" '#u8(0 255) (bytevector 0 255))

;; --- vectors and pairs, nested and improper ------------------------------
(write '#(1 "two" #\3 (4) #(5) 6.5 sym))
(newline)
(write '#(1 #(2 #(3 #(4)))))
(newline)
(write '(1 . 2))
(newline)
(write '(1 2 . 3))
(newline)
(write '(1 (2 (3 (4 (5 . 6)))) #(7 (8)) "s" #\c 9/2 1.5 1+2i))
(newline)
(chk "vector-value" '#(1 2 3) (vector 1 2 3))
(chk "improper-tail" (list (cdr (cdr '(1 2 . 3)))) (list 3))

;; --- the immediates ------------------------------------------------------
(write (list #t #f '()))
(newline)
(chk "nil-is-null" (list (null? '())) (list #t))

;; --- nesting just inside MAX_CONSTANT_DEPTH (256) ------------------------
;; A cdr chain of 250 pairs reaches depth 250 in `writeConstant`; 257 or more
;; does not survive at all (see sbc-constant-depth.scm).
(define long250
  '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27
    28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52
    53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77
    78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101
    102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119
    120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137
    138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155
    156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173
    174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191
    192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209
    210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227
    228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245
    246 247 248 249))
(chk "deep-list-250" (list (length long250) (list-ref long250 249)) (list 250 249))
