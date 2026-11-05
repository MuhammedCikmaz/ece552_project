# Project 3: single-cycle processor

The processor implements the course's RV32I instructions and EBREAK. Each
active cycle fetches, decodes, executes, and retires one instruction. PC and
register-file updates occur on the rising clock edge. Instruction and data
memories remain in the supplied, unchanged testbench.

## Files

| File | Responsibility |
| --- | --- |
| `rtl/hart.v` | PC and halt state, operand/writeback muxes, branch targets, commit and retirement |
| `rtl/decode.v` | Instruction legality, source usage, immediate format and control signals |
| `rtl/alu.v` | Project 2 arithmetic, logic, shifts and comparisons |
| `rtl/rf.v` | Project 2 register file, instantiated with `BYPASS_EN=0` |
| `rtl/imm.v` | Project 2 immediate extraction, with comments cleaned up and unused R immediate set to zero |
| `rtl/lsu.v` | Aligned memory address, byte masks, store lanes and load extension |
| `schematic.pdf` | Complete datapath, control connections, and signal widths |
| `{r,i,s,b,u,j}_type_schematic.pdf` | Brightly highlighted example paths for all six formats |
| `schematics/*.svg` | Editable vector sources; open with Inkscape or another SVG editor |

The architectural state is the PC, register file, and halted bit. All other
processor logic is combinational. The fetch/decode/execute/memory/writeback
comments identify logical stages, without adding pipeline registers.

## Important behavior

- Branch comparison uses the original two register operands. A separate
  PC-relative adder computes the branch/JAL target in the same cycle.
- JAL/JALR write `PC+4`. JALR clears bit 0 of `rs1+immediate`, then checks
  four-byte instruction alignment. Only taken branches check target alignment.
- Memory addresses sent to the testbench are word-aligned. Low address bits
  select byte lanes and constant-wiring muxes. Unselected memory-read lanes may
  be unknown; they cannot affect a byte/halfword load result.
- Loads/stores, register writes and retirement are disabled during reset and
  after halt. EBREAK retires once, holds the PC, and latches the halted state.
- Illegal encodings and misaligned accesses assert `o_retire_trap` and suppress
  register writes and memory accesses. **Design choice:** because the course
  interface has no privileged trap handler, a trapping instruction advances to
  `PC+4`. The published assignment does not specify a trap-vector policy.
- FENCE is supported as a no-op because memory operations complete in order.
  ECALL, CSR operations and unsupported ISA extensions report a trap.
- Unused source-register addresses are reported as zero. Instructions that do
  not write a register, or target x0, report destination register zero.

## Run and validate

Install Icarus Verilog (`iverilog`, `vvp`) and GNU RISC-V binutils
(`riscv64-unknown-elf-as`, `riscv64-unknown-elf-objcopy`). Install the course
checker following `../python-ece552/README.md`; use Python 3.10–3.13 for its
pinned `pyslang` dependency. From this directory:

```sh
make validate
make test
make sim PROGRAM=01add
```

`make test` runs all five supplied programs through both a differential
testbench and the unchanged course testbench. The independent Python ISA model
checks every retired instruction's PC, next PC, source values, destination
value, trap/halt status and enabled memory transaction. Additional tests cover:

- Signed/unsigned arithmetic boundaries, all shift amounts, x0, and register dependencies.
- Every byte/halfword lane, extension, partial stores, negative offsets and unknown inactive lanes.
- All six branch conditions both taken and untaken, backward loops, long offsets,
  JAL/JALR link values, odd JALR targets and `rd == rs1`.
- Illegal encodings and misaligned accesses, including suppression of side effects.
- Eight reproducible randomized programs, a nonzero reset address, and restarting after halt.

Generated traces and `results.json` are under `build/tests/`. These are local
tests, not the private Gradescope suite; passing them does not establish an
autograder score. The test runner accepts `IVERILOG`, `IVERILOG_FLAGS`, `VVP`,
and `RISCV_PREFIX` environment variables for alternate tool installations.

To use the original Docker assembler workflow instead, run
`make PROGRAM=01add` in `tests/asm`, then compile `rtl/*.v` with `tb/tb.v` and
run from `tb`, where that workflow writes `program.mem`.

## Schematics and submission

Install CairoSVG in a Python environment, then run `make schematics` to
regenerate all seven SVGs and PDFs. Each PDF contains the same complete design
and control-net tables; the six type-specific PDFs highlight sample execution
paths. The SVG files are the editable graphical sources.

Fill in group member names in `project3.txt`, remove unused member lines, and
run `make submission`. This produces `submission.zip` with the six RTL files,
seven required PDFs, and `project3.txt`, all at the archive root. The packager
warns if group names are still placeholders. Do not submit testbench, test,
script or build files. Upload the deliverables to your group on Gradescope;
this workspace task does not upload them.

Requirements: <https://ece552.wiscarch.org/project3/>

Verilog rules: <https://ece552.wiscarch.org/rules/>
