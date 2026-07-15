; Interpreter-tier control "primitive" bodies, PLAIN element access.
; Models what a bytevector-u8-ref / -set! primitive compiles to: a bounds check
; plus one single aligned element access. The dispatch_bench driver calls these
; through a volatile function pointer (an opaque, non-inlinable indirect call in
; a separate object -- no LTO), so the per-element access sits behind realistic
; call overhead exactly as every -ref/-set! sits behind VM NativeFn dispatch.
; Compared against prim_unordered.ll, the ONLY difference is the atomic
; annotation on the load/store -- memo §9.4's plain-vs-unordered control.

define i64 @prim_ref(ptr %base, i64 %i, i64 %len) {
entry:
  %ok = icmp ult i64 %i, %len
  br i1 %ok, label %do, label %oob
do:
  %p = getelementptr i8, ptr %base, i64 %i
  %x = load i8, ptr %p, align 1
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
  store i8 %b, ptr %p, align 1
  br label %ret
ret:
  ret void
}
