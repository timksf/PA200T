set bluej_bus_width 76
set bluej_bus_ignore 0x8000000000000000000

proc bluej_bus_request {write address data} {
    if {$address < 0 || $address > 0xffffffff || ($address & 3)} {
        error "expected an aligned 32-bit address"
    }

    set high [expr {($write << 6) | ($address >> 26)}]
    set low  [expr {(($address & 0x3ffffff) << 38) |
                    (($data & 0xffffffff) << 6) | (15 << 2) | 3}]

    # OpenOCD 0.12 otherwise parses a zero-padded value as octal.
    return [format "0x%03x%016llx" $high $low]
}

proc bluej_bus_scan {tap value} {
    global bluej_bus_width

    set raw [string tolower [string trim [drscan $tap $bluej_bus_width $value]]]
    return [string range "0000000000000000000$raw" end-18 end]
}

proc bluej_bus_access {tap instruction write address data} {
    global bluej_bus_ignore

    irscan $tap $instruction
    bluej_bus_scan $tap [bluej_bus_request $write $address $data]

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

proc bluej_bus_write32 {tap address data {instruction 0x23}} {
    set result [bluej_bus_access $tap $instruction 1 $address $data]
    echo [format "write 0x%08x: 0x%08x" $address [expr {$data & 0xffffffff}]]
    return $result
}