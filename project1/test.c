#include <inttypes.h>
#include <stdio.h>

extern uint32_t mystery(const uint32_t x);

// Performs a vector dot product between the 32 bit unsigned integer
// arrays A and B of length len. The arrays are guaranteed to be the
// same length (len items).
int main(void)
{
    printf("%" PRIu32 "\n", mystery(33));
}
