# RTL8211FD RGMII, bank 14 (3.3 V). PHY straps: RXDLY on, TXDLY off, so the
# FPGA forwards TXC shifted by 90 degrees and samples RXD centered on RXC.

create_clock -period 8.000 -name rgmii_rxc [get_ports CLK_rgmii_rxc]

set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports  CLK_rgmii_rxc]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVCMOS33} [get_ports  rgmii_rx_ctl]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[0]}]
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[1]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[2]}]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[3]}]

set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports  rgmii_txc]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports  rgmii_tx_ctl]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports {rgmii_txd[0]}]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports {rgmii_txd[1]}]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports {rgmii_txd[2]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports {rgmii_txd[3]}]

# RX: RTL8211FD datasheet table 58 with RXDLY, data valid 1.2 ns before and
# after every RXC edge (center-aligned DDR template, launch on the opposite edge).
set rgmii_rx_ports [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set rgmii_rx_dv    1.2
set_input_delay -clock rgmii_rxc -max [expr {4.0 - $rgmii_rx_dv}] $rgmii_rx_ports
set_input_delay -clock rgmii_rxc -min $rgmii_rx_dv                $rgmii_rx_ports
set_input_delay -clock rgmii_rxc -max [expr {4.0 - $rgmii_rx_dv}] $rgmii_rx_ports -clock_fall -add_delay
set_input_delay -clock rgmii_rxc -min $rgmii_rx_dv                $rgmii_rx_ports -clock_fall -add_delay
