/*
 * cpi -- measure your processor's CPI on real hardware, live.
 *
 * This is the program the Project 6 demo is built around. It runs a fixed
 * workload, reads the cycle and retired-instruction counters either side of
 * it, and puts the resulting CPI on the displays. Change the memory latencies
 * with the switches, press reset, and watch the number move.
 *
 *   HEX5                   instruction memory latency in cycles (1..8)
 *   HEX4                   data memory latency in cycles        (1..8)
 *   HEX3 HEX2 HEX1 HEX0    CPI x 100, in decimal -- read 1111 as 11.11
 *   LEDR[3:0]              initiation interval, in unary: N lit means N cycles
 *   LEDR[9]                which workload is running (0 = ALU, 1 = load/store)
 *
 *   KEY0          switch between the two workloads
 *
 * The two workloads separate the two things memory latency costs you:
 *
 *   Workload 0 (ALU) touches no data memory at all. 
 *   Workload 1 (load/store) walks a small array.
 *
 *
 * Build: riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Os -nostdlib
 *        -ffreestanding -fno-builtin
 */

/* ------------------------------------------------------------------ *
 * Memory-mapped I/O. Duplicated in each program for now; this block
 * moves to a shared io.h once the peripheral set settles.
 * ------------------------------------------------------------------ */
#define MMIO_BASE   0x80000000u

#define LEDR        (*(volatile unsigned int *)(MMIO_BASE + 0x00))  /* W, 10 bits          */
#define KEY_EDGE    (*(volatile unsigned int *)(MMIO_BASE + 0x0C))  /* R, sticky presses   */
#define KEY_ACK     (*(volatile unsigned int *)(MMIO_BASE + 0x10))  /* W, clear the latch  */
#define HEX_VAL     (*(volatile unsigned int *)(MMIO_BASE + 0x14))  /* W, 24b -> 6 nibbles */
#define HEX_EN      (*(volatile unsigned int *)(MMIO_BASE + 0x20))  /* W, 6b digit enable  */
#define CYCLES      (*(volatile unsigned int *)(MMIO_BASE + 0x24))  /* R, cycle counter    */
#define INSTRET     (*(volatile unsigned int *)(MMIO_BASE + 0x28))  /* R, retire counter   */
#define MEM_CFG     (*(volatile unsigned int *)(MMIO_BASE + 0x2C))
/* MEM_CFG: [3:0] instruction memory latency, [7:4] data memory latency,
   [11:8] initiation interval. All three were sampled from the switches while
   reset was held. */

/*
 * Stop the compiler moving the workload across a counter read. The counter
 * reads are volatile so they keep their order relative to each other, but the
 * workload itself is ordinary code and could otherwise be hoisted out from
 * between them, which would measure nothing at all. This emits no
 * instructions; it only constrains the optimiser.
 */
#define BARRIER()   __asm__ __volatile__("" ::: "memory")

/* ------------------------------------------------------------------ *
 * Arithmetic this ISA cannot do directly.
 * ------------------------------------------------------------------ */

/* Restoring shift-and-subtract division. One bit per iteration, 32 of them. */
static unsigned udiv(unsigned n, unsigned d)
{
    unsigned q = 0u;
    unsigned r = 0u;
    int i;

    if (d == 0u)
        return 0u;

    for (i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1u);
        if (r >= d) {
            r -= d;
            q |= (1u << i);
        }
    }

    return q;
}

/* x * 100 == x*64 + x*32 + x*4. Written out so no __mulsi3 call appears. */
static unsigned mul100(unsigned x)
{
    return (x << 6) + (x << 5) + (x << 2);
}

/* x * 10 == x*8 + x*2. */
static unsigned mul10(unsigned x)
{
    return (x << 3) + (x << 1);
}

/* ------------------------------------------------------------------ *
 * The workloads.
 * ------------------------------------------------------------------ */

/* Somewhere for a result to go, so the optimiser cannot delete the work. */
static volatile unsigned sink;

/*
 * Workload 0: arithmetic only, no loads or stores. An xorshift-flavoured
 * mixing loop -- the particular arithmetic does not matter, only that it is
 * all register-to-register and that it has a loop-carried dependency, so
 * forwarding has something to do.
 */
static unsigned work_alu(void)
{
    unsigned x = 1u;
    unsigned i;

    for (i = 0u; i < 400u; i++) {
        x += i;
        x ^= (x << 3);
        x ^= (x >> 5);
        x += (x << 1);          /* x * 3, as shifts */
    }

    return x;
}

/*
 * Workload 1: the same shape of loop, but every iteration touches memory.
 * Three passes over a 64-word array: fill it, sum it, then rewrite it.
 *
 * buf lives in .bss (never initialised at compile time), which this SoC
 * requires: pressing reset restarts the processor but does not reload memory,
 * so an initialised mutable global would come back holding whatever the
 * previous run left in it.
 */
#define BUF_WORDS 64u
static unsigned buf[BUF_WORDS];

static unsigned work_mem(void)
{
    unsigned s = 0u;
    unsigned i;

    for (i = 0u; i < BUF_WORDS; i++)
        buf[i] = i;

    for (i = 0u; i < BUF_WORDS; i++)
        s += buf[i];

    for (i = 0u; i < BUF_WORDS; i++)
        buf[i] = s ^ buf[i];

    return s;
}

/* ------------------------------------------------------------------ *
 * Measurement and display.
 * ------------------------------------------------------------------ */

/*
 * Run one workload between two reads of the counters and return CPI x 100.
 *
 * The four counter reads are themselves instructions that retire and cycles
 * that elapse, so they are inside the measurement. Each workload is a few
 * thousand instructions and the overhead is a handful, so the error is well
 * under a percent -- but it is not zero, and it is worth knowing it is there.
 */
static unsigned measure(unsigned which)
{
    unsigned c0, i0, c1, i1;
    unsigned dc, di;

    c0 = CYCLES;
    i0 = INSTRET;

    BARRIER();
    sink = which ? work_mem() : work_alu();
    BARRIER();

    c1 = CYCLES;
    i1 = INSTRET;

    dc = c1 - c0;
    di = i1 - i0;

    if (di == 0u)
        return 0u;

    /*
     * CPI x 100 = (cycles * 100) / instructions. The multiply by 100 is what
     * limits how long a workload may be: dc must stay under about 42 million
     * or the product wraps 32 bits. These workloads are a few thousand
     * cycles, so there is a lot of headroom.
     */
    return udiv(mul100(dc), di);
}

/*
 * Pack a value 0..9999 into four decimal digits, one per nibble. Four
 * digits (not three) because HEX3 used to show which workload was running --
 * a whole 7-segment digit spent on one bit -- and three digits of CPI x 100
 * pegs at 9.99, which the ILAT=8 configs this lab is built around exceed
 * (measured ~11.1 at ILAT=8, DLAT=1). Moving the workload indicator to
 * LEDR[9] frees HEX3 for a fourth digit, which is all this needed: the
 * 0.01 CPI resolution stays exactly the same, there's just room for two
 * integer digits now instead of one.
 */
static unsigned bcd4(unsigned v)
{
    unsigned d3, d2, d1, d0;

    if (v > 9999u)
        v = 9999u;              /* peg rather than wrap: 9999 means "off scale" */

    d3 = udiv(v, 1000u);
    v -= mul10(mul100(d3));     /* mul10(mul100(x)) == x*1000, no __mulsi3 */
    d2 = udiv(v, 100u);
    v -= mul100(d2);
    d1 = udiv(v, 10u);
    v -= mul10(d1);
    d0 = v;

    return (d3 << 12) | (d2 << 8) | (d1 << 4) | d0;
}

int main(void)
{
    unsigned which = 0u;        /* 0 = ALU workload, 1 = load/store workload */

    HEX_EN  = 0x3Fu;            /* all six digits */
    KEY_ACK = 0xFu;             /* clear any press latched during reset */

    for (;;) {
        unsigned cfg  = MEM_CFG;
        unsigned ilat = cfg & 0xFu;
        unsigned dlat = (cfg >> 4) & 0xFu;
        unsigned ivl  = (cfg >> 8) & 0xFu;

        unsigned cpi100 = measure(which);

        HEX_VAL = (ilat << 20)
                | (dlat << 16)
                | bcd4(cpi100);

        /* The interval in unary on the low bits, so it needs no decoding by
           eye: (1 << ivl) - 1 lights exactly ivl LEDs. The workload bit lives
           on LEDR[9] -- ivl's unary encoding never reaches past LEDR[3], so
           the two never collide -- freeing HEX3 above for a fourth CPI
           digit instead of a single bit. */
        LEDR = (((1u << ivl) - 1u) & 0x3FFu) | (which << 9);

        /* KEY0 switches workload. The latch is sticky, so a press is never
           missed even though we only look once per measurement. */
        if (KEY_EDGE & 0x1u) {
            KEY_ACK = 0x1u;
            which ^= 1u;
        }
    }

    return 0;   /* not reached */
}
