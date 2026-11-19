# Build and simulate the FPGA demo with your processor.
#
#   make memtest           check the memories on their own (no processor needed)
#   make sim               build the software and run the testbench
#   make sweep             run the testbench at the demo's configurations
#   make lint              elaborate the synthesisable design only
#   make clean
#
# Put your processor (hart.v and whatever it instantiates) in this directory,
# next to soc_core.v, then fill in the hart instantiation in soc_core.v.
#
# ILAT, DLAT and IVL set the instruction memory latency, the data memory
# latency and the initiation interval, the same way the switches do on the
# board:
#
#   make sim ILAT=1 DLAT=1 IVL=1       fastest memory
#   make sim ILAT=1 DLAT=8 IVL=1       slow data memory only
#   make sim ILAT=8 DLAT=1 IVL=1       slow instruction memory only
#   make sim ILAT=8 DLAT=8 IVL=4       slowest memory
#
# The two latencies are independent. The middle two lines above are the
# configurations the demo is built around: one of them will hurt your CPI far
# more than the other, and predicting which is the exercise.
#
# `make sweep` runs all of them in order, which is also the quickest way to
# find out whether your processor really waits on mem_valid or has a fixed
# latency baked into it somewhere.
#
# See https://ece552.wiscarch.org/project6_ec/ for the full walkthrough.

PROG    ?= cpi
ILAT    ?= 4
DLAT    ?= 4
IVL     ?= 2
# One image does everything: it carries the RISC-V toolchain and Icarus Verilog.
IMAGE   ?= coderkalyan/ece552-tools:latest
SW_DIR  := ../sw

# Your files plus soc_core.v; the finished wrapper modules live in ip/.
SRC     := $(wildcard *.v)
IP      := $(wildcard ip/*.v)
# The two testbenches are simulation only and must never reach Quartus.
IP_SYN  := $(filter-out ip/soc_tb.v ip/mem_tb.v,$(IP))
# mem_tb needs only the memory subsystem, not a processor.
MEM_SRC := ip/mem_pipe.v ip/imem.v ip/dbus.v ip/mmio.v ip/mem_tb.v

DOCKER  := MSYS_NO_PATHCONV=1 docker run --rm -v "$(CURDIR)":/src -w /src $(IMAGE)

.PHONY: sim sweep memtest lint image clean help
.DEFAULT_GOAL := help

help:
	@echo "make memtest           test the memories alone -- no processor needed"
	@echo "make sim               build software + run the testbench"
	@echo "make sweep             run the testbench at the demo configurations"
	@echo "make lint              elaborate the synthesisable design"
	@echo "make clean             remove simulation artifacts"
	@echo
	@echo "programs: cpi"
	@echo "memory:   ILAT=1..8 (instruction memory latency)"
	@echo "          DLAT=1..8 (data memory latency)"
	@echo "          IVL=1..4  (initiation interval, both memories)"
	@echo
	@echo "full walkthrough: https://ece552.wiscarch.org/project6_ec/"
	@echo
	@echo "your files here: $(SRC)"
	@if [ ! -f hart.v ]; then echo; echo "  !! hart.v not found -- copy your processor into this directory"; fi

image:
	@"$(MAKE)" -C $(SW_DIR) --no-print-directory PROGRAM=$(PROG) mem >/dev/null
	@cp $(SW_DIR)/build/$(PROG).mem program.mem
	@cp $(SW_DIR)/build/$(PROG).lane0.mem program.lane0.mem
	@cp $(SW_DIR)/build/$(PROG).lane1.mem program.lane1.mem
	@cp $(SW_DIR)/build/$(PROG).lane2.mem program.lane2.mem
	@cp $(SW_DIR)/build/$(PROG).lane3.mem program.lane3.mem

# Checks the wrapper's memories against the Project 6 memory contract at every
# latency and interval the switches can select. Does not involve your
# processor at all, so a failure here is a problem with the lab files, not
# with your design -- say so on Piazza.
memtest: image
	@$(DOCKER) bash -c '\
	  iverilog -g2005 -o mem_tb.out -s mem_tb $(MEM_SRC) && \
	  vvp mem_tb.out'

sim: image
	@$(DOCKER) bash -c '\
	  iverilog -g2005 -o soc_tb.out -s soc_tb $(SRC) $(IP) && \
	  vvp soc_tb.out +PROG=$(PROG) +ILAT=$(ILAT) +DLAT=$(DLAT) +IVL=$(IVL)'

# If your processor passes at one latency and fails at another, it is reading
# a fixed latency somewhere instead of waiting on mem_valid. The Gradescope
# tests vary the latency too, so this is worth getting right regardless.
sweep: image
	@$(DOCKER) bash -c '\
	  iverilog -g2005 -o soc_tb.out -s soc_tb $(SRC) $(IP) || exit 1; \
	  for cfg in "1 1 1" "1 8 1" "8 1 1" "8 8 1" "8 8 4"; do \
	    set -- $$cfg; \
	    echo; \
	    vvp soc_tb.out +PROG=$(PROG) +ILAT=$$1 +DLAT=$$2 +IVL=$$3 || exit 1; \
	  done'

# Elaborates the board top level -- the same file set Quartus will synthesise.
# Catches a syntax error or a bad port name in seconds instead of twenty
# minutes into a compile.
lint:
	@$(DOCKER) iverilog -g2005 -o /dev/null -s de1soc_top $(SRC) $(IP_SYN)
	@echo "  lint ok"

clean:
	rm -f soc_tb.out mem_tb.out program.mem program.lane0.mem program.lane1.mem \
	      program.lane2.mem program.lane3.mem *.vcd
