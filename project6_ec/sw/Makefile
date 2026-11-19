# Build a C demo program into program.mem for the FPGA wrapper.
#
#   make PROGRAM=cpi           build, check, and emit build/program.mem
#   make PROGRAM=cpi disasm    show the disassembly
#   make all                   build every program
#   make clean
#
# The cross-toolchain runs in a container so the flow is identical on Windows,
# macOS and the CAE machines. This is the same image the course's assembly tests
# use, so you already have it.
#
# Full walkthrough: https://ece552.wiscarch.org/project6_ec/

PROGRAM   ?= cpi
IMAGE     ?= coderkalyan/ece552-tools:latest
MEM_BYTES ?= 4096

PROGRAMS  := cpi

CROSS   := riscv64-unknown-elf-
CFLAGS  := -march=rv32i -mabi=ilp32 -Os \
           -nostdlib -ffreestanding -fno-builtin \
           -msmall-data-limit=0 -fno-tree-loop-distribute-patterns \
           -Wall -Wextra -Werror
LDFLAGS := -T link.ld -Wl,-Map,build/$(PROGRAM).map

# MSYS_NO_PATHCONV stops Git Bash rewriting container paths like /src
DOCKER  := MSYS_NO_PATHCONV=1 docker run --rm -v "$(CURDIR)":/src -w /src $(IMAGE)

.PHONY: all mem disasm clean help
ifeq ($(origin PROGRAM),command line)
.DEFAULT_GOAL := mem
else
.DEFAULT_GOAL := help
endif

help:
	@echo "make PROGRAM=<name>          compile, link, flatten, convert -> build/program.mem"
	@echo "make PROGRAM=<name> disasm   show the disassembly"
	@echo "make all                     build every program"
	@echo "make clean                   remove build/"
	@echo
	@echo "programs: $(PROGRAMS)"
	@echo "e.g.      make PROGRAM=cpi"
	@echo
	@echo "cpi   measures CPI on the board -- the program this lab is about"

build/$(PROGRAM).elf: $(PROGRAM).c crt0.S link.ld
	@mkdir -p build
	$(DOCKER) $(CROSS)gcc $(CFLAGS) $(LDFLAGS) crt0.S $(PROGRAM).c -o $@

mem: build/$(PROGRAM).elf
	@$(DOCKER) bash -c 'set -e; \
	  $(CROSS)objdump -d build/$(PROGRAM).elf > build/$(PROGRAM).dis; \
	  $(CROSS)objdump -h build/$(PROGRAM).elf > build/$(PROGRAM).sec; \
	  $(CROSS)objcopy -O binary --pad-to=$(MEM_BYTES) --gap-fill=0 \
	      build/$(PROGRAM).elf build/$(PROGRAM).bin; \
	  od -An -v -tx4 -w4 build/$(PROGRAM).bin | sed "s/^ //" > build/$(PROGRAM).mem'
	@python tools/isa_check.py $(PROGRAM) build/$(PROGRAM).dis build/$(PROGRAM).sec \
	    --max-bytes $(MEM_BYTES)
	@python tools/split_lanes.py build/$(PROGRAM).bin build/$(PROGRAM)
	@cp build/$(PROGRAM).mem build/program.mem
	@cp build/$(PROGRAM).lane0.mem build/program.lane0.mem
	@cp build/$(PROGRAM).lane1.mem build/program.lane1.mem
	@cp build/$(PROGRAM).lane2.mem build/program.lane2.mem
	@cp build/$(PROGRAM).lane3.mem build/program.lane3.mem
	@echo "      ->  build/program.mem (+ 4 byte-lane files for dbus.v)"

disasm: build/$(PROGRAM).elf
	@$(DOCKER) $(CROSS)objdump -d $<

all:
	@for p in $(PROGRAMS); do "$(MAKE)" --no-print-directory PROGRAM=$$p mem || exit 1; done

clean:
	rm -rf build
