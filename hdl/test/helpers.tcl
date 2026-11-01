set bluej_bus_width 76
set bluej_bus_ignore 0x8000000000000000000

proc bluej_bus_request {write address data {strobe 0xf}} {
    if {$address < 0 || $address > 0xffffffff || ($address & 3)} {
        error "expected an aligned 32-bit address"
    }
    if {$strobe < 0 || $strobe > 0xf} {
        error "expected a 4-bit byte strobe"
    }

    set high [expr {($write << 6) | ($address >> 26)}]
    set low  [expr {(($address & 0x3ffffff) << 38) |
                    (($data & 0xffffffff) << 6) | ($strobe << 2) | 3}]

    # OpenOCD 0.12 otherwise parses a zero-padded value as octal.
    return [format "0x%03x%016llx" $high $low]
}

proc bluej_bus_scan {tap value} {
    global bluej_bus_width

    set raw [string tolower [string trim [drscan $tap $bluej_bus_width $value]]]
    return [string range "0000000000000000000$raw" end-18 end]
}

proc bluej_bus_access {tap instruction write address data {strobe 0xf}} {
    global bluej_bus_ignore

    irscan $tap $instruction
    bluej_bus_scan $tap [bluej_bus_request $write $address $data $strobe]

    for {set poll 0} {$poll < 16} {incr poll} {
        set raw     [bluej_bus_scan $tap $bluej_bus_ignore]
        set status  [expr 0x[string range $raw 0 2]]
        set payload [expr 0x[string range $raw 3 18]]

        if {$status & 0x080} {
            error "BlueJ request dropped"
        }
        if {$status & 0x100} {
            continue
        }
        if {$status & 0x200} {
            if {($status & 0x400) || ($payload & 3)} {
                error "BlueJ bus error"
            }
            return [expr {($payload >> 6) & 0xffffffff}]
        }
    }

    error "BlueJ response timeout"
}

proc bluej_bus_read32 {tap address {instruction 0x23}} {
    set value [bluej_bus_access $tap $instruction 0 $address 0]
    echo [format "read  0x%08x: 0x%08x" $address $value]
    return $value
}

proc bluej_bus_write32 {tap address data {instruction 0x23} {strobe 0xf}} {
    set result [bluej_bus_access $tap $instruction 1 $address $data $strobe]
    echo [format "write 0x%08x: 0x%08x" $address [expr {$data & 0xffffffff}]]
    return $result
}

# Set baud in bits/second and enable UART, preserving the stop-bit setting.
# The default clock matches the 125 MHz system clock (PLL output, see src/PA200T_PLL.bsv).
# Returns the programmed clocks-per-bit prescaler (rounded to nearest).
# Example: bluej_uart_configure pa200t.tap 115200
proc bluej_uart_configure {tap baud {clock_hz 125000000} {instruction 0x23}} {
    if {![string is integer -strict $baud] || $baud <= 0} {
        error "expected a positive integer baud rate"
    }
    if {![string is integer -strict $clock_hz] || $clock_hz <= 0} {
        error "expected a positive integer UART clock frequency in Hz"
    }
    set prescaler [expr {($clock_hz + $baud / 2) / $baud}]
    if {$baud > $clock_hz || $prescaler < 1 || $prescaler > 0xffff} {
        error "baud rate is outside the UART's 16-bit prescaler range"
    }

    set control [bluej_bus_access $tap $instruction 0 0x04 0]
    bluej_bus_access $tap $instruction 1 0x08 $prescaler
    bluej_bus_access $tap $instruction 1 0x04 [expr {$control | 1}]
    return $prescaler
}

# Call bluej_uart_configure to set BAUD and enable CTRL before sending.
# Example: bluej_uart_send pa200t.tap "Hello\r\n"
# Sends byte-valued characters without adding a newline; returns bytes queued.
# The final byte may still be transmitting when this returns.
proc bluej_uart_send {tap text {instruction 0x23}} {
    set bytes {}
    foreach character [split $text ""] {
        scan $character %c byte
        if {$byte < 0 || $byte > 255} {
            error "expected byte-valued UART characters (0..255)"
        }
        lappend bytes $byte
    }

    if {[llength $bytes] == 0} {
        return 0
    }
    if {([bluej_bus_access $tap $instruction 0 0x04 0] & 1) == 0} {
        error "UART is disabled; configure BAUD (0x08) and enable CTRL (0x04) first"
    }

    foreach byte $bytes {
        for {set poll 0} {$poll < 1000} {incr poll} {
            set status [bluej_bus_access $tap $instruction 0 0x0c 0]
            if {$status & 0x400} {
                break
            }
            sleep 1
        }
        if {$poll == 1000} {
            error "UART TXREADY timeout"
        }
        # TXDATA accepts only the low byte lane, unlike full-word CSRs.
        bluej_bus_access $tap $instruction 1 0x10 $byte 0x1
    }

    return [llength $bytes]
}

# ---------------------------------------------------------------------------
# MDIO (Clause 22) master, mapped at 0x1000 on the system bus.
# Registers: ADDRESS 0x00, WRITE_DATA 0x04, COMMAND 0x08, STATUS 0x0c,
#            READ_DATA 0x10, DIVIDER 0x14, PHY_RESET 0x18 (offsets from base).
# PA200T-Starlite: RTL8211FD at PHY address 1 (PHYAD[2:0] = 001).
# ---------------------------------------------------------------------------
set bluej_mdio_base 0x1000

proc bluej_mdio_reg {offset} {
    global bluej_mdio_base
    return [expr {$bluej_mdio_base + $offset}]
}

# Set the MDC divider and pulse the PHY reset.
# MDC = f_clk / (2 * divider); 100 gives 1 MHz at 200 MHz, leaving a 500 ns
# high phase for the PHY's 300 ns max MDIO output delay.
# RTL8211F: reset low >= 10 ms, then wait >= 30 ms before MDIO access.
proc bluej_mdio_init {tap {divider 100} {instruction 0x23}} {
    bluej_bus_access $tap $instruction 1 [bluej_mdio_reg 0x14] $divider
    bluej_bus_access $tap $instruction 1 [bluej_mdio_reg 0x18] 0
    sleep 20
    bluej_bus_access $tap $instruction 1 [bluej_mdio_reg 0x18] 1
    sleep 100
}

proc bluej_mdio_wait {tap instruction} {
    for {set poll 0} {$poll < 100} {incr poll} {
        set status [bluej_bus_access $tap $instruction 0 [bluej_mdio_reg 0x0c] 0]
        if {($status & 1) == 0} {
            return $status
        }
    }
    error "MDIO busy timeout"
}

proc bluej_mdio_start {tap phy reg command instruction} {
    if {$phy < 0 || $phy > 31 || $reg < 0 || $reg > 31} {
        error "expected PHY and register addresses in 0..31"
    }
    # clear DONE and NO_ACK, then issue the command
    bluej_bus_access $tap $instruction 1 [bluej_mdio_reg 0x0c] 6
    bluej_bus_access $tap $instruction 1 [bluej_mdio_reg 0x00] [expr {($phy << 8) | $reg}]
    bluej_bus_access $tap $instruction 1 [bluej_mdio_reg 0x08] $command
    return [bluej_mdio_wait $tap $instruction]
}

# Returns the 16-bit register value. Errors if the PHY does not acknowledge.
proc bluej_mdio_read {tap phy reg {instruction 0x23}} {
    set status [bluej_mdio_start $tap $phy $reg 1 $instruction]
    if {$status & 4} {
        error [format "MDIO read phy %d reg %d: no ACK (PHY in reset or wrong address?)" $phy $reg]
    }
    set value [bluej_bus_access $tap $instruction 0 [bluej_mdio_reg 0x10] 0]
    echo [format "mdio  phy %d reg %2d: 0x%04x" $phy $reg $value]
    return $value
}

proc bluej_mdio_write {tap phy reg data {instruction 0x23}} {
    bluej_bus_access $tap $instruction 1 [bluej_mdio_reg 0x04] [expr {$data & 0xffff}]
    bluej_mdio_start $tap $phy $reg 2 $instruction
    echo [format "mdio  phy %d reg %2d <- 0x%04x" $phy $reg [expr {$data & 0xffff}]]
}

# ---- UDP endpoint (0x2000) and traffic generator (0x3000) ---------------
# Register maps: libraries/ethernet/README.md and libraries/ethernet/src/UdpTraffic.bsv.

set bluej_eth_base     0x2000
set bluej_traffic_base 0x3000

proc bluej_ip {dotted} {
    set parts [split $dotted .]
    if {[llength $parts] != 4} {
        error "expected a dotted IPv4 address, got $dotted"
    }
    set value 0
    foreach part $parts {
        if {![string is integer -strict $part] || $part < 0 || $part > 255} {
            error "expected a dotted IPv4 address, got $dotted"
        }
        set value [expr {($value << 8) | $part}]
    }
    return $value
}

proc bluej_eth_write {tap offset data instruction} {
    global bluej_eth_base
    bluej_bus_access $tap $instruction 1 [expr {$bluej_eth_base + $offset}] $data
}

proc bluej_eth_read {tap offset instruction} {
    global bluej_eth_base
    return [bluej_bus_access $tap $instruction 0 [expr {$bluej_eth_base + $offset}] 0]
}

# Program addresses with the MAC stopped, clear the ARP cache, then enable
# TX and RX with the standard 12-byte inter-frame gap.
# mac: 12 hex digits, e.g. 025041323030 for 02:50:41:32:30:30.
proc bluej_eth_setup {tap mac local_ip netmask gateway peer_ip src_port dst_port {instruction 0x23}} {
    set mac [string map {: ""} $mac]
    if {![string is xdigit -strict $mac] || [string length $mac] != 12} {
        error "expected a 48-bit MAC address"
    }
    bluej_eth_write $tap 0x04 0 $instruction
    scan [string range $mac 4 11] %x mac_low
    scan [string range $mac 0 3]  %x mac_high
    bluej_eth_write $tap 0x08 $mac_low  $instruction
    bluej_eth_write $tap 0x0c $mac_high $instruction
    bluej_eth_write $tap 0x10 [bluej_ip $local_ip] $instruction
    bluej_eth_write $tap 0x14 [bluej_ip $gateway]  $instruction
    bluej_eth_write $tap 0x18 [bluej_ip $netmask]  $instruction
    bluej_eth_write $tap 0x1c [bluej_ip $peer_ip]  $instruction
    bluej_eth_write $tap 0x20 [expr {($dst_port << 16) | ($src_port & 0xffff)}] $instruction
    bluej_eth_write $tap 0x28 1 $instruction
    bluej_eth_write $tap 0x30 0xffffffff $instruction
    bluej_eth_write $tap 0x34 0xffffffff $instruction
    bluej_eth_write $tap 0x04 0x0c03 $instruction
    echo [format "eth   %s mac %s -> peer %s, udp %d -> %d" $local_ip $mac $peer_ip $src_port $dst_port]
}

# Prints machine-readable "ETH <name> <value>" lines.
proc bluej_eth_status {tap {instruction 0x23}} {
    foreach {offset name} {0x2c STATUS 0x30 PROTOCOL_EVENTS 0x34 MAC_EVENTS} {
        echo [format "ETH %s 0x%08x" $name [bluej_eth_read $tap $offset $instruction]]
    }
}

# Waits for the PHY link (BMSR bit 2) and returns the speed in Mb/s from the
# RTL8211F PHYSR (page 0xa43, register 0x1a, bits 5:4).
proc bluej_phy_wait_link {tap phy {timeout_ms 10000} {instruction 0x23}} {
    for {set waited 0} {$waited < $timeout_ms} {incr waited 250} {
        # BMSR link status latches low; the second read is current
        bluej_mdio_read $tap $phy 1 $instruction
        if {[bluej_mdio_read $tap $phy 1 $instruction] & 4} {
            bluej_mdio_write $tap $phy 31 0xa43 $instruction
            set physr [bluej_mdio_read $tap $phy 0x1a $instruction]
            bluej_mdio_write $tap $phy 31 0 $instruction
            set speed [lindex {10 100 1000 0} [expr {($physr >> 4) & 3}]]
            echo [format "PHY link up, %d Mb/s, %s duplex" $speed [expr {($physr & 8) ? "full" : "half"}]]
            return $speed
        }
        sleep 250
    }
    error "PHY link did not come up within $timeout_ms ms"
}

proc bluej_traffic_write {tap offset data instruction} {
    global bluej_traffic_base
    bluej_bus_access $tap $instruction 1 [expr {$bluej_traffic_base + $offset}] $data
}

proc bluej_traffic_read {tap offset instruction} {
    global bluej_traffic_base
    return [bluej_bus_access $tap $instruction 0 [expr {$bluej_traffic_base + $offset}] 0]
}

# Generate count packets (0: until bluej_traffic_stop) of length payload bytes
# to the endpoint's PEER_IP, with gap idle cycles after each packet.
proc bluej_traffic_tx {tap length count {gap 0} {instruction 0x23}} {
    bluej_traffic_write $tap 0x10 $length $instruction
    bluej_traffic_write $tap 0x14 $count  $instruction
    bluej_traffic_write $tap 0x18 $gap    $instruction
    bluej_traffic_write $tap 0x04 1       $instruction
}

proc bluej_traffic_stop {tap {instruction 0x23}} {
    bluej_traffic_write $tap 0x08 1 $instruction
}

# Clear the RX counters and count only packets to port (0: any port).
proc bluej_traffic_rx_clear {tap {port 0} {instruction 0x23}} {
    bluej_traffic_write $tap 0x20 $port $instruction
    bluej_traffic_write $tap 0x0c 1     $instruction
}

proc bluej_traffic_echo {tap enable {instruction 0x23}} {
    bluej_traffic_write $tap 0x1c [expr {$enable ? 1 : 0}] $instruction
}

# Prints machine-readable "TRAFFIC <name> <value>" lines.
proc bluej_traffic_dump {tap {instruction 0x23}} {
    foreach {offset name} {
        0x24 STATUS 0x10 TX_LENGTH 0x28 TX_PACKETS 0x2c TX_CYCLES
        0x30 RX_PACKETS 0x34 RX_BYTES 0x38 RX_CYCLES 0x3c RX_SEQ_ERRORS
        0x40 RX_BAD_FRAMES 0x44 RX_IGNORED
    } {
        echo [format "TRAFFIC %s %u" $name [bluej_traffic_read $tap $offset $instruction]]
    }
}
