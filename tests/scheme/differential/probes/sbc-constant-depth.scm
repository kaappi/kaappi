;; Regression probe for kaappi#2113 (FIXED): a quoted list past 256 elements
;; — and a cyclic literal — used to write a cache entry that could never be
;; loaded, recompiling AND rewriting the same `.sbc` on every run, forever,
;; while `kaappi cache status` called the entry "current".
;;
;; Audit v2, Phase 4E.  Was the one KNOWN_NEVER_HIT entry; now an ordinary
;; probe whose entry must HIT (run-differential.sh's permanent-miss check
;; fails the run otherwise).
;;
;; Mechanism, then.  The two halves of the codec disagreed about who enforces
;; the limits: `writeConstant` TRUNCATED to TAG_NIL at depth > 256 and
;; enforced no other size cap, while `readConstant` REJECTED the whole file at
;; the same depth (plus five more caps the writer never checked).  A proper
;; list reached one depth level per cdr step, so the cliff sat at 257
;; elements.
;;
;; Now.  Format v11 closes both halves of that asymmetry:
;;
;;   - list spines are walked ITERATIVELY on both sides, so depth counts
;;     nesting (car descent / vector elements) and a long quoted list is
;;     cacheable — the 300-element list below HITs;
;;   - a cyclic literal terminates via TAG_BACKREF (kaappi#2111) and HITs;
;;   - what still exceeds a cap (e.g. nesting deeper than 256 via car) is
;;     REFUSED by the writer with `--timings` reason "constant exceeds .sbc
;;     limits", so no unloadable entry exists for `cache status` to misreport
;;     — and `cache status` now dry-runs each current-build entry's body,
;;     reporting one the reader rejects as "unloadable" rather than
;;     "current" (timings-1515.sh and the Zig unit tests pin the refusal;
;;     src/cache.zig's tests pin the status states).
;;
;; The discriminating control relationship with sbc-constants-aggregate.scm's
;; 250-element list (which always HIT) still holds — both now sit on the same
;; side of the repaired cliff.

(define past-cliff '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256 257 258 259 260 261 262 263 264 265 266 267 268 269 270 271 272 273 274 275 276 277 278 279 280 281 282 283 284 285 286 287 288 289 290 291 292 293 294 295 296 297 298 299))
(display (list (length past-cliff) (car past-cliff) (list-ref past-cliff 299)))
(newline)

;; A cyclic literal, which used to reach the old depth guard by a different
;; route and now round-trips as a back-reference.
(define cyc '#0=(1 2 . #0#))
(display (list (car cyc) (cadr cyc) (caddr cyc) (eq? cyc (cddr cyc))))
(newline)
