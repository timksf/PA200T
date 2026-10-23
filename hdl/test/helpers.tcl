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
# The default clock matches the 200 MHz clock in constr/system.xdc.
# Returns the programmed clocks-per-bit prescaler (rounded to nearest).
# Example: bluej_uart_configure pa200t.tap 115200
proc bluej_uart_configure {tap baud {clock_hz 200000000} {instruction 0x23}} {
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
