; Interpreter-tier control "primitive" bodies, UNORDERED element access.
; Identical to prim_plain.ll except the element load/store carry `unordered`
; atomic ordering -- the encoding the P1 memo §4 prescribes for the interpreter
; tier ("one ordering annotation on the single load/store inside a primitive is
; noise against VM dispatch"). This file exists to measure that claim directly.

define i64 @prim_ref(ptr %base, i64 %i, i64 %len) {
entry:
  %ok = icmp ult i64 %i, %len
  br i1 %ok, label %do, label %oob
do:
  %p = getelementptr i8, ptr %base, i64 %i
  %x = load atomic i8, ptr %p unordered, align 1
  %z = zext i8 %x to i64
  ret i64 %z
oob:
  ret i64 -1
}

define void @prim_set(ptr %base, i64 %i, i64 %len, i64 %v) {
entry:
  %ok = icmp ult i64 %i, %len
  br i1 %ok, label %do, label %ret
do:
  %p = getelementptr i8, ptr %base, i64 %i
  %b = trunc i64 %v to i8
  store atomic i8 %b, ptr %p unordered, align 1
  br label %ret
ret:
  ret void
}
