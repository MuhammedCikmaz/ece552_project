PYTHON ?= python3
ECE552 ?= ece552
IVERILOG ?= iverilog
VVP ?= vvp
IVERILOG_FLAGS ?=
RISCV_PREFIX ?= riscv64-unknown-elf-
PROGRAM ?= 01add

.PHONY: test validate schematics sim submission clean

test:
	IVERILOG="$(IVERILOG)" IVERILOG_FLAGS="$(IVERILOG_FLAGS)" VVP="$(VVP)" RISCV_PREFIX="$(RISCV_PREFIX)" $(PYTHON) scripts/test_processor.py

validate:
	$(ECE552) validate -w rtl/*.v

schematics:
	$(PYTHON) scripts/draw_schematics.py

# Assemble with local GNU binutils and run the original course testbench.
sim:
	mkdir -p build/sim
	$(RISCV_PREFIX)as -march=rv32i -mabi=ilp32 tests/asm/$(PROGRAM).asm -o build/sim/program.o
	$(RISCV_PREFIX)objcopy -O binary -j .text --pad-to=0x400 build/sim/program.o build/sim/program.bin
	$(PYTHON) -c 'from pathlib import Path; b=Path("build/sim/program.bin").read_bytes(); Path("build/sim/program.mem").write_text(" ".join(format(x,"02x") for x in b)+"\n")'
	$(IVERILOG) $(IVERILOG_FLAGS) -g2005 -s hart_tb -o build/sim/hart.vvp rtl/*.v tb/tb.v
	cd build/sim && $(VVP) hart.vvp

submission: validate
	$(PYTHON) scripts/package_submission.py

clean:
	rm -rf build
