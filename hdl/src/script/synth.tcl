set script_dir [file dirname [file normalize [info script]]]
set src_dir    [file normalize [file join $script_dir ..]]
set bluej_dir  [file normalize [file join $src_dir .. libraries bluej hdl src script]]
set report     [file join $project_dir $project_name]
set constr_dir [file join $script_dir .. constr]

read_xdc [file join $constr_dir system.xdc]
read_xdc [file join $constr_dir gpio.xdc]
read_xdc [file join $constr_dir uart.xdc]
read_xdc [file join $constr_dir jtag.xdc]
read_xdc [file join $constr_dir mdio.xdc]
read_xdc [file join $constr_dir rgmii.xdc]

synth_design -top $top_module
puts "Finished synth_design"

# verilog-ethernet CDC and IO timing constraints; each script only acts on
# instances of its module, so they are harmless without the UDP subsystem
set eth_dir [file normalize [file join $src_dir .. .. dep verilog-ethernet]]
foreach eth_tcl {
    syn/vivado/rgmii_phy_if.tcl
    syn/vivado/eth_mac_1g_rgmii.tcl
    syn/vivado/eth_mac_fifo.tcl
    lib/axis/syn/vivado/axis_async_fifo.tcl
    lib/axis/syn/vivado/sync_reset.tcl
} {
    source [file join $eth_dir $eth_tcl]
}

# needs the PLL output clocks, which only exist after synthesis
read_xdc [file join $constr_dir cdc.xdc]

# implement
opt_design

report_timing_summary -file $project_dir/${project_name}_tim1.rpt
report_utilization -file $project_dir/${project_name}_util1.rpt
report_drc -file $project_dir/${project_name}_drc1.rpt
puts "Finished opt_design"

place_design

report_timing_summary -file $project_dir/${project_name}_tim2.rpt
report_utilization -file $project_dir/${project_name}_util2.rpt
puts "Finished place_design"

route_design
puts "Finished route_design"

phys_opt_design
puts "Finished phys_opt_design"

report_timing_summary -file $project_dir/${project_name}_tim3.rpt
report_utilization -file $project_dir/${project_name}_util3.rpt
report_drc -file $project_dir/${project_name}_drc3.rpt
report_methodology -file $project_dir/${project_name}_method3.rpt

write_checkpoint $project_dir/${project_name}_physopt.dcp -force

# Tag outputs with the final setup WNS, e.g. PA200T_out_-0.601ns.bit
set wns_path [get_timing_paths -max_paths 1 -nworst 1 -setup]
set wns [expr {[llength $wns_path] ? [get_property SLACK $wns_path] : ""}]
set wns_tag [expr {[string is double -strict $wns] ? [format "%.3fns" $wns] : "na"}]
puts "Final WNS: $wns_tag"

set out_base       ${project_name}_out_${wns_tag}
set bitstream_file [file join $project_dir ${out_base}.bit]
write_bitstream -force -file $bitstream_file

# PA200T-Starlite U7: W25Q128JVSIQ, 128 Mbit (16 MiB), quad SPI.
# Hardware Manager configuration memory part: w25q128jvq-spi-x1_x2_x4.
# Boot from address zero; SPI bus width and voltage are set in system.xdc.
write_cfgmem -force -format mcs -size 16 -interface SPIx4 \
    -loadbit [list up 0x00000000 $bitstream_file] \
    -file [file join $project_dir ${out_base}.mcs]
puts "Finished configuration memory generation"
