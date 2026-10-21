# ifndef ETHERNET_MK_INCLUDED
# ETHERNET_MK_INCLUDED := 1

# ETHERNET_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
# ETHERNET_DEP_ROOT := $(abspath $(ETHERNET_ROOT)/../../../dep)
# ETHERNET_RTL_ROOT := $(ETHERNET_DEP_ROOT)/verilog-ethernet

# ETHERNET_BLUEAXI_MK := $(firstword $(wildcard $(CURDIR)/libraries/*/BlueAXI.mk $(ETHERNET_DEP_ROOT)/BlueAXI/BlueAXI.mk))
# include $(ETHERNET_BLUEAXI_MK)
# ETHERNET_BLUECSR_MK := $(firstword $(wildcard $(CURDIR)/libraries/*/BlueCSR.mk $(ETHERNET_DEP_ROOT)/bluecsr/BlueCSR.mk))
# include $(ETHERNET_BLUECSR_MK)

# EXTRA_BSV_LIBS += $(ETHERNET_ROOT)/wrap $(ETHERNET_ROOT)/src
# VERILOGDIR_EXTRAS += $(ETHERNET_RTL_ROOT)/rtl $(ETHERNET_RTL_ROOT)/lib/axis/rtl

# endif
