ETHERNET_ROOT := $(abspath ..)
REPO_ROOT := $(abspath ../../../..)
BSC ?= bsc
IVERILOG ?= iverilog
VVP ?= vvp
BUILD ?= build
BSC_LIBDIR ?= $(shell $(BSC) -help 2>&1 | sed -n 's/^Bluespec directory: //p')
BSV_PATH := +:$(REPO_ROOT)/dep/BlueAXI/src:$(REPO_ROOT)/dep/bluecsr/src:$(ETHERNET_ROOT)/wrap:$(ETHERNET_ROOT)/src
RTL_ROOT := $(REPO_ROOT)/dep/verilog-ethernet
VSEARCH := +:$(RTL_ROOT)/rtl:$(RTL_ROOT)/lib/axis/rtl

.PHONY: test test-regs test-udp test-rgmii test-mdio clean
test: test-regs test-udp test-rgmii test-mdio

test-regs:
	@mkdir -p $(BUILD)/regs
	@$(BSC) -u -sim -g mkTestEthernetRegs -p $(BSV_PATH) -bdir $(BUILD)/regs -simdir $(BUILD)/regs -info-dir $(BUILD)/regs TestEthernetRegs.bsv > $(BUILD)/regs/compile.log 2>&1 || { cat $(BUILD)/regs/compile.log; exit 1; }
	@$(BSC) -sim -e mkTestEthernetRegs -p +:$(BUILD)/regs -bdir $(BUILD)/regs -simdir $(BUILD)/regs -o $(BUILD)/regs/test > $(BUILD)/regs/link.log 2>&1 || { cat $(BUILD)/regs/link.log; exit 1; }
	@timeout 30s $(BUILD)/regs/test > $(BUILD)/regs/run.log 2>&1
	@cat $(BUILD)/regs/run.log
	@grep -q '^PASS:' $(BUILD)/regs/run.log

# BVI modules require Verilog simulation rather than Bluesim.
test-udp:
	@mkdir -p $(BUILD)/udp
	@$(BSC) -u -verilog -g mkTestEthernetUdp -p $(BSV_PATH) -bdir $(BUILD)/udp -vdir $(BUILD)/udp -info-dir $(BUILD)/udp TestEthernetUdp.bsv > $(BUILD)/udp/compile.log 2>&1 || { cat $(BUILD)/udp/compile.log; exit 1; }
	@$(BSC) -verilog -e mkTestEthernetUdp -vsim iverilog -p +:$(BUILD)/udp -bdir $(BUILD)/udp -vdir $(BUILD)/udp -vsearch $(VSEARCH) -o $(BUILD)/udp/test > $(BUILD)/udp/link.log 2>&1 || { cat $(BUILD)/udp/link.log; exit 1; }
	@timeout 30s $(BUILD)/udp/test > $(BUILD)/udp/run.log 2>&1
	@cat $(BUILD)/udp/run.log
	@grep -q '^PASS:' $(BUILD)/udp/run.log

test-rgmii:
	@mkdir -p $(BUILD)/rgmii
	@$(BSC) -u -verilog -g mkTestEthernetRgmii -p $(BSV_PATH) -bdir $(BUILD)/rgmii -vdir $(BUILD)/rgmii -info-dir $(BUILD)/rgmii TestEthernetRgmii.bsv > $(BUILD)/rgmii/compile.log 2>&1 || { cat $(BUILD)/rgmii/compile.log; exit 1; }
	@$(IVERILOG) -g2012 -s test_rgmii -y $(RTL_ROOT)/rtl -y $(RTL_ROOT)/lib/axis/rtl -y $(BSC_LIBDIR)/Verilog -o $(BUILD)/rgmii/test $(BUILD)/rgmii/mkTestEthernetRgmii.v test_rgmii.v > $(BUILD)/rgmii/link.log 2>&1 || { cat $(BUILD)/rgmii/link.log; exit 1; }
	@timeout 30s $(VVP) $(BUILD)/rgmii/test > $(BUILD)/rgmii/run.log 2>&1 || { cat $(BUILD)/rgmii/run.log; exit 1; }
	@cat $(BUILD)/rgmii/run.log
	@grep -q '^PASS:' $(BUILD)/rgmii/run.log

test-mdio:
	@mkdir -p $(BUILD)/mdio
	@$(BSC) -u -sim -g mkTestMdio -p $(BSV_PATH) -bdir $(BUILD)/mdio -simdir $(BUILD)/mdio -info-dir $(BUILD)/mdio TestMdio.bsv > $(BUILD)/mdio/compile.log 2>&1 || { cat $(BUILD)/mdio/compile.log; exit 1; }
	@$(BSC) -sim -e mkTestMdio -p +:$(BUILD)/mdio -bdir $(BUILD)/mdio -simdir $(BUILD)/mdio -o $(BUILD)/mdio/test > $(BUILD)/mdio/link.log 2>&1 || { cat $(BUILD)/mdio/link.log; exit 1; }
	@timeout 30s $(BUILD)/mdio/test > $(BUILD)/mdio/run.log 2>&1
	@cat $(BUILD)/mdio/run.log
	@grep -q '^PASS:' $(BUILD)/mdio/run.log
	@$(BSC) -u -verilog -g mkMdioAxiLiteElab -p $(BSV_PATH) -bdir $(BUILD)/mdio -vdir $(BUILD)/mdio -info-dir $(BUILD)/mdio TestMdio.bsv > $(BUILD)/mdio/verilog.log 2>&1 || { cat $(BUILD)/mdio/verilog.log; exit 1; }
	@$(IVERILOG) -g2012 -s mkMdioAxiLiteElab -y $(BSC_LIBDIR)/Verilog -o $(BUILD)/mdio/elab $(BUILD)/mdio/mkMdioAxiLiteElab.v > $(BUILD)/mdio/elab.log 2>&1 || { cat $(BUILD)/mdio/elab.log; exit 1; }

clean:
	rm -rf $(BUILD)
