    .text
    .globl mystery
mystery:
    # t5 = 8
    addi t5, zero, 8

    # t5 = t5 * 2^2
    # = 32
    slli t5, t5, 2

    # t0 = var - 32
    sub  t0, a0, t5

    # t1 = t0 {var - 32} * 4
    slli t1, t0, 2

    # t1 = (t0{var - 32} * 4) + (var - 32)
    add  t1, t1, t0

    # t2 = 0
    addi t2, zero, 0

    # t3 = (t0{var - 32} * 4) + (var - 32)
    # t3 = (5var - 160)
    addi t3, t1, 0

    # t4 = 9
    addi t4, zero, 9
loop:
    # if t3 < t4; done
    # if t3 < 9
    blt  t3, t4, done

    # t3 = t3 - t4
    # t3 = ((t0{var - 32} * 4) + (var - 32)) - 9
    # t3 = (5var - 160) - 9 // first iteration
    # so this is basically dividing by 9 
    # and counting how many times we can divide
    sub  t3, t3, t4

    # t2 += 1
    addi t2, t2, 1

    # just go back to loop
    beq  zero, zero, loop
done:
    addi a0, t2, 0
    jalr zero, 0(ra)
