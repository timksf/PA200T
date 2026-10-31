ifndef ETHERNET_MK_INCLUDED
ETHERNET_MK_INCLUDED := 1

ETHERNET_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ETHERNET_DEP_ROOT := $(abspath $(ETHERNET_ROOT)/../../../dep)
ETHERNET_RTL_ROOT := $(ETHERNET_DEP_ROOT)/verilog-ethernet

ETHERNET_BLUEAXI_MK := $(firstword $(wildcard $(CURDIR)/libraries/*/BlueAXI.mk $(ETHERNET_DEP_ROOT)/BlueAXI/BlueAXI.mk))
include $(ETHERNET_BLUEAXI_MK)
ETHERNET_BLUECSR_MK := $(firstword $(wildcard $(CURDIR)/libraries/*/BlueCSR.mk $(ETHERNET_DEP_ROOT)/bluecsr/BlueCSR.mk))
include $(ETHERNET_BLUECSR_MK)

EXTRA_BSV_LIBS += $(ETHERNET_ROOT)/wrap $(ETHERNET_ROOT)/src
# Upstream RTL left out:
#   ssio_sdr_in_diff.v passes IODDR_STYLE to ssio_sdr_in without declaring it.
#   udp_checksum_gen.v drops headers when its header FIFO fills (small packets
#   at line rate); the patched copy in rtl/ replaces it.
ETHERNET_RTL_EXCLUDE := ssio_sdr_in_diff.v udp_checksum_gen.v
ETHERNET_RTL_FILES := $(filter-out $(addprefix %/,$(ETHERNET_RTL_EXCLUDE)), \
                        $(wildcard $(ETHERNET_RTL_ROOT)/rtl/*.v))

VERILOGDIR_EXTRAS += $(wildcard $(ETHERNET_ROOT)/rtl/*.v) $(ETHERNET_RTL_FILES) $(ETHERNET_RTL_ROOT)/lib/axis/rtl

endif
