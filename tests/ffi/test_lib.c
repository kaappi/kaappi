/* Comprehensive C library for FFI coverage testing */
#include <string.h>
#include <stdlib.h>

/* 0-arg functions with various return types */
int get_zero(void) { return 0; }
int get_fortytwo(void) { return 42; }
long get_long_max(void) { return 9999999L; }
double get_pi(void) { return 3.14159265; }
float get_half(void) { return 0.5f; }
const char *get_greeting(void) { return "hello from C"; }
void do_nothing(void) { }

/* 1-arg: int -> various */
int negate(int x) { return -x; }
int identity_int(int x) { return x; }
int abs_val(int x) { return x < 0 ? -x : x; }
long int_to_long(int x) { return (long)x; }
double int_to_double(int x) { return (double)x; }
void consume_int(int x) { (void)x; }

/* 1-arg: long -> various */
long identity_long(long x) { return x; }
long negate_long(long x) { return -x; }
void consume_long(long x) { (void)x; }

/* 1-arg: double -> various */
double identity_double(double x) { return x; }
double negate_double(double x) { return -x; }
int double_to_int(double x) { return (int)x; }
float double_to_float(double x) { return (float)x; }
void consume_double(double x) { (void)x; }

/* 1-arg: float -> various */
float identity_float(float x) { return x; }

/* 1-arg: string -> various */
int string_length(const char *s) { int n = 0; while (s[n]) n++; return n; }
long string_length_long(const char *s) { long n = 0; while (s[n]) n++; return n; }
void consume_string(const char *s) { (void)s; }
double string_to_double(const char *s) { return atof(s); }

/* 2-arg: (int, int) -> various */
int add_ints(int a, int b) { return a + b; }
int multiply(int a, int b) { return a * b; }
long add_ints_long(int a, int b) { return (long)a + (long)b; }
void consume_two_ints(int a, int b) { (void)a; (void)b; }

/* 2-arg: (double, double) -> various */
double add_doubles(double a, double b) { return a + b; }
int compare_doubles(double a, double b) { return a < b ? -1 : (a > b ? 1 : 0); }
void consume_two_doubles(double a, double b) { (void)a; (void)b; }

/* 2-arg: (long, long) -> various */
long add_longs(long a, long b) { return a + b; }

/* 2-arg: (string, string) -> various */
int strcmp_wrap(const char *a, const char *b) { return strcmp(a, b); }
long strlen_sum(const char *a, const char *b) { return (long)strlen(a) + (long)strlen(b); }
void consume_two_strings(const char *a, const char *b) { (void)a; (void)b; }

/* 2-arg: (float, float) -> float */
float add_floats(float a, float b) { return a + b; }

/* 3-arg functions */
int sum3(int a, int b, int c) { return a + b + c; }
long sum3_long(long a, long b, long c) { return a + b + c; }
double sum3_double(double a, double b, double c) { return a + b + c; }
int clamp(int x, int lo, int hi) { return x < lo ? lo : (x > hi ? hi : x); }

/* 3-arg with string,int,int -> int (like strncmp-ish) */
int substr_char(const char *s, int idx, int def) {
    int len = 0;
    while (s[len]) len++;
    if (idx < 0 || idx >= len) return def;
    return (int)s[idx];
}

/* 3-arg: string,string,int -> int */
int strncmp_wrap(const char *a, const char *b, int n) {
    return strncmp(a, b, (size_t)n);
}

/* Pointer functions for FFI dispatch coverage */
void *identity_ptr(void *p) { return p; }
int ptr_is_null(void *p) { return p == 0 ? 1 : 0; }
void consume_ptr(void *p) { (void)p; }
long ptr_to_long(void *p) { return (long)p; }
double ptr_to_double(void *p) { (void)p; return 0.0; }

/* 2-arg pointer functions */
int ptr_ptr_cmp(void *a, void *b) { return a == b ? 1 : 0; }
void *ptr_ptr_first(void *a, void *b) { (void)b; return a; }
void consume_ptr_ptr(void *a, void *b) { (void)a; (void)b; }
int ptr_int_sum(void *p, int n) { (void)p; return n; }
void ptr_int_noop(void *p, int n) { (void)p; (void)n; }
int int_ptr_sum(int n, void *p) { (void)p; return n; }
void int_ptr_noop(int n, void *p) { (void)n; (void)p; }
long ptr_long_sum(void *p, long n) { (void)p; return n; }

/* 1-arg: string -> pointer (returns pointer to first char) */
const void *str_to_ptr(const char *s) { return (const void *)s; }
/* 1-arg: long -> pointer */
void *long_to_ptr(long n) { return (void *)n; }
/* 1-arg: int -> pointer */
void *int_to_ptr(int n) { return (void *)(long)n; }

/* 2-arg: (string, string) -> pointer */
const void *str_str_ptr(const char *a, const char *b) { (void)b; return (void *)a; }

/* 4-arg functions */
int sum4(int a, int b, int c, int d) { return a + b + c + d; }
long sum4_long(long a, long b, long c, long d) { return a + b + c + d; }
double sum4_double(double a, double b, double c, double d) { return a + b + c + d; }
