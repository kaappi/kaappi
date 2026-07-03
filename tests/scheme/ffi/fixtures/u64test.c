#include <stdint.h>
#include <stddef.h>

uint64_t echo_u64(uint64_t x) { return x; }
size_t echo_size(size_t x) { return x; }
uint64_t check_u64(uint64_t x, uint64_t y) { return x == y; }
