# MDIO smoke test via the custom TAP: read the RTL8211FD PHY ID.
# Usage: openocd -f pa200t_jlink_mdio.tcl
# No Ethernet cable is needed; MDIO only needs the PHY powered and out of reset.

source [file join [file dirname [info script]] pa200t_jlink.tcl]

set tap   pa200t.tap
set instr 0x3
set phy   1

bluej_mdio_init $tap 100 $instr

set id1 [bluej_mdio_read $tap $phy 2 $instr]
set id2 [bluej_mdio_read $tap $phy 3 $instr]
set oui [expr {($id1 << 6) | ($id2 >> 10)}]
echo [format "PHY ID 0x%04x%04x: OUI 0x%06x model 0x%02x rev %d" \
    $id1 $id2 $oui [expr {($id2 >> 4) & 0x3f}] [expr {$id2 & 0xf}]]

# Expected RTL8211F(D): PHYID1 0x001c, PHYID2 0xc916 (revision nibble may differ)
if {$id1 == 0x001c && ($id2 & 0xfff0) == 0xc910} {
    echo "PASS: RTL8211F detected at PHY address $phy"
} else {
    echo "FAIL: unexpected PHY ID"
}

set bmsr [bluej_mdio_read $tap $phy 1 $instr]
echo [format "BMSR: link %s, autoneg %s" \
    [expr {($bmsr & 0x4) ? "up" : "down"}] \
    [expr {($bmsr & 0x20) ? "complete" : "pending"}]]

shutdown
