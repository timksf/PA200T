# Load a bitstream into FPGA SRAM over the on-board FT232H (volatile; flash is untouched).
# Usage: openocd -f pa200t_load.tcl -c "pld load xc7.pld ../build/PA200T/PA200T_out_<wns>ns.bit; shutdown"
adapter driver ftdi
ftdi vid_pid 0x0403 0x6014
ftdi layout_init 0x0008 0x000b
adapter speed 10000
transport select jtag
jtag newtap xc7 tap -irlen 6 -expected-id 0x13636093
pld create xc7.pld virtex2 -chain-position xc7.tap
init
