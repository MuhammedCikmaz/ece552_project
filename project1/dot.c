#include <inttypes.h>
#include <stdio.h>

extern uint32_t umul(const uint32_t x, const uint32_t y);

// Performs a vector dot product between the 32 bit unsigned integer
// arrays A and B of length len. The arrays are guaranteed to be the
// same length (len items).
uint32_t dot(const uint32_t *const A, const uint32_t *const B, const size_t len)
{
    uint32_t sum = 0;
    for (int i = 0; i < len; i++){
        sum += umul(A[i], B[i]);
    }

    return sum;
}
