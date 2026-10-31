# Clock domain crossings. Read after synth_design because the PLL output
# clocks are derived from the netlist.
#
# Every path between these groups crosses through a bsc synchronizer
# (SyncFIFO, SyncBit, SyncResetA) or is an asynchronous pin (UART RX), so the
# groups are unrelated for timing. CLKOUT0 and CLKOUT1 stay in one group: the
# RGMII TX clock forwarding relies on their 90 degree relation.
# rgmii_rxc is left out on purpose: the verilog-ethernet scripts bound its
# crossings with set_max_delay -datapath_only, which a clock group would override.

set pll_clocks [get_clocks -of_objects [get_pins -of_objects \
    [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter {REF_PIN_NAME =~ CLKOUT*}]]

set_clock_groups -asynchronous \
    -group [get_clocks clk_200] \
    -group $pll_clocks \
    -group [get_clocks -quiet {jtag_tck jtag_tck3 jtag_tck4}]
