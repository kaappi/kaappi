;; Probe / KNOWN PERMANENT MISS: a constant nested deeper than 256 is written
;; to the cache and can never be read back, so this file recompiles AND
;; rewrites its `.sbc` on every single run — and `kaappi cache status` calls
;; the entry "current".
;;
;; Audit v2, Phase 4E.  Tracked as kaappi#2113.  Not a KNOWN_DIFFS entry: cold
;; and warm agree byte for byte, because the warm run is simply a second cold
;; run.  That is precisely the hazard — tier (d) is vacuous for this file while
;; the harness's "cache exercised" count says it is covered, which is why
;; run-differential.sh now checks that a written entry actually HITs.
;;
;; Mechanism.  The two halves of the codec disagree about who enforces the
;; limits:
;;
;;   - `writeConstant` (src/bytecode_file_write.zig) TRUNCATES to TAG_NIL at
;;     `depth > 256` and enforces no other size limit at all.
;;   - `readConstant` (src/bytecode_file_read.zig) REJECTS at
;;     `depth > MAX_CONSTANT_DEPTH` (256) and additionally rejects
;;     MAX_STRING_BYTES, MAX_VECTOR_LEN, MAX_BYTEVECTOR_LEN, MAX_BIGNUM_LIMBS
;;     and MAX_CONSTANTS_PER_FUNCTION overruns.
;;
;; The reader being the stricter half is what keeps this from being a silent
;; wrong answer: the truncated tail is never observed, because the whole file
;; is rejected first.  The cost is paid instead as an invisible permanent miss.
;;
;; The cliff is exact.  A quoted proper list of N elements reaches depth N in
;; `writeConstant` (each cdr step is one level), so:
;;
;;     N = 256   ->  warm run HITs
;;     N = 257   ->  warm run MISSes, forever
;;
;; A vector literal longer than MAX_VECTOR_LEN (262144) behaves identically,
;; as does a cyclic literal such as `'#0=(1 . #0#)`, which recurses to the
;; guard on its own.
;;
;; The list below is 300 elements: past the cliff, and small enough that the
;; wasted recompile is cheap.  The discriminating control is
;; sbc-constants-aggregate.scm's 250-element list, which does HIT.

(define past-cliff '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256 257 258 259 260 261 262 263 264 265 266 267 268 269 270 271 272 273 274 275 276 277 278 279 280 281 282 283 284 285 286 287 288 289 290 291 292 293 294 295 296 297 298 299))
(display (list (length past-cliff) (car past-cliff) (list-ref past-cliff 299)))
(newline)

;; A cyclic literal reaches the same guard by a different route.
(define cyc '#0=(1 2 . #0#))
(display (list (car cyc) (cadr cyc) (caddr cyc) (eq? cyc (cddr cyc))))
(newline)
