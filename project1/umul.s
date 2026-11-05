## Author: Muhammed Cikmaz
##
## You may implement the following with any of the instructions in the RV32I instruction set
## and described in the reference sheet. Do not use any of the mul[h][s][u] instructions which
## are *not* described in the reference sheet. Remember to respect the calling convention - if
## you choose to use any of the callee saved registers s[0-11], remember to save them to the
## stack before reusing them (note, you should not need to do this but are free to do so).
##
## [Description]
## Multiplies two 32-bit *unsigned* numbers and provides a 32-bit *unsigned* result
## consisting of the lower 32 bits of the product.
##
## [Arguments]
## a0 = multiplicand
## a1 = multiplier
##
## [Returns]
## a0 = 32-bit product
    .text
    .globl umul
umul:
    # This dummy code adds the two operands and returns the result.
    # Replace with your implementation.

    #directory
    # t0 for knowing index of the bit we are workign on

    # t1 we will use this to store the current bit we will be multiplying

    # t2 will be used to store temp calculated number

    # t3 will be used to stored the number that will be returned

    # t4 use to store 31 (max iteration cnt)

    # t5 will be used for masking

    # zero t0, t1, t2, t3
    # we will use t0 to know on what bit we are, which will be use to determine how many times
    # we need to shift left
    and t0, t0, zero;
    and t1, t1, zero;
    and t2, t2, zero;
    and t3, t3, zero;

    addi t4, zero, 32;
    addi t5, zero, 1;

    loop_start:
        sll t5, t5, t0;
        and t1, a0, t5;

        # so i need to mupliply a0 with that bit. All i need to know is if the bit is 0 or 1
        # because i will just and it with that bit anyway. 
        # to get there I need an if statement, since if 0 will require us to do less work we can just
        # skip to skip_if if 0 
        beq t1, zero, end_if;
            # if we are here, that means our bit is 1, so we need to sll a1 t0
            # many times, and add it with t3
            add t2, zero, a1;
            sll t2, t2, t0;
            add t3, t3, t2;
        end_if:

        addi t5, zero, 1;
        addi t0, t0, 1; # increment t0
    bltu t0, t4, loop_start;

    # return a0
    add a0, zero, t3;

    jalr zero, 0(ra)
