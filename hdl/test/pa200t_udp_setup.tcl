# Bring up the UDP endpoint: release the PHY reset, wait for the link and
# program addresses. Override any setting with -c before -f, for example
#   openocd -c "set udp_peer_ip 192.168.1.10" -f pa200t_udp_setup.tcl
# Used by udp_bitrate.py; ends with "UDP SETUP DONE".

source [file join [file dirname [info script]] pa200t_jlink.tcl]

foreach {name value} {
    udp_mac         025041323030
    udp_local_ip    192.168.178.250
    udp_netmask     255.255.255.0
    udp_gateway     192.168.178.1
    udp_peer_ip     192.168.178.23
    udp_src_port    5000
    udp_dst_port    5001
    udp_phy_reset   1
} {
    if {![info exists $name]} { set $name $value }
}

set tap   pa200t.tap
set instr 0x3
set phy   1

if {$udp_phy_reset} {
    bluej_mdio_init $tap 100 $instr
}
bluej_phy_wait_link $tap $phy 10000 $instr

bluej_eth_setup $tap $udp_mac $udp_local_ip $udp_netmask $udp_gateway \
    $udp_peer_ip $udp_src_port $udp_dst_port $instr
bluej_traffic_echo $tap 0 $instr
bluej_traffic_rx_clear $tap $udp_src_port $instr
bluej_eth_status $tap $instr

echo "UDP SETUP DONE"
shutdown
