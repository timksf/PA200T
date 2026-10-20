create_clock -period 250.000 -name jtag_tck [get_ports {CLK_tck}]

set_input_delay -clock [get_clocks jtag_tck] -clock_fall -min -5.000 [get_ports {TMS TDI}]
set_input_delay -clock [get_clocks jtag_tck] -clock_fall -max 20.000 [get_ports {TMS TDI}]

set_output_delay -clock [get_clocks jtag_tck] -min -5.000 [get_ports {TDO}]
set_output_delay -clock [get_clocks jtag_tck] -max 20.000 [get_ports {TDO}]

set_property -dict {PACKAGE_PIN J20 IOSTANDARD LVCMOS33} [get_ports {CLK_tck}]
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports {TMS}]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports {TDO}]
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports {TDI}]
