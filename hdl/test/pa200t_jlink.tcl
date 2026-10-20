adapter driver jlink
transport select jtag
adapter speed 1000
reset_config none

source [file join [file dirname [info script]] helpers.tcl]

# custom tap via pins
jtag newtap pa200t tap -irlen 3 -expected-id 0x0000402f

init
scan_chain

runtest 5
