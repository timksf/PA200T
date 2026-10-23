# MDIO master

`Mdio::mkMdioMaster` is a native Bluespec Clause 22 master with `Put#(MdioRequest)`
and `Get#(MdioResponse)`, one outstanding command, a 32-bit preamble on every
frame, and MSB-first PHY/register/data fields. It uses the enclosing logic clock
throughout: MDC comes from a counter and clock enables, with no derived clock
domain or Verilog protocol wrapper.

`MdioCsr::mkMdioCsr` provides a standalone `BlueCSR_ifc#(32, 32, 0)` peripheral.
`mkMdioAxiLite` exposes that same register map through the existing BlueCSR
AXI4-Lite adapter. The composable `mdio_csrs` definition uses local offsets and is
mounted with `csr_add_context('h40, mdio_csrs)` in `ethernet_csrs`;
both `mkUdpRgmiiCsr` and `mkUdpRgmiiAxiLite` expose its
`mdio` interface and `phy_reset_n` output. There is one unified Ethernet register
file, rather than a separate management bus.

| Standalone | Ethernet | Register | Fields and reset |
| --- | --- | --- | --- |
| `0x00` | `0x40` | ADDRESS, RW | PHY register bits 4:0; PHY address bits 12:8; both 0 |
| `0x04` | `0x44` | WRITE_DATA, RW | Data bits 15:0 = 0 |
| `0x08` | `0x48` | COMMAND, WO | Write `1` to read or `2` to write |
| `0x0c` | `0x4c` | STATUS | BUSY bit 0, RO; DONE bit 1 and NO_ACK bit 2, sticky W1C; reset 0 |
| `0x10` | `0x50` | READ_DATA, RO | Most recent read data bits 15:0 = 0 |
| `0x14` | `0x54` | DIVIDER, RW | MDC half-period in logic-clock cycles, bits 15:0 = 64 |
| `0x18` | `0x58` | PHY_RESET, RW | Bit 0 releases active-low PHY reset; reset 0 holds the PHY in reset |

The divider is clamped to at least four cycles. The MDC frequency is
`f_logic / (2 * max(DIVIDER, 4))`; its default is approximately 977 kHz at a
125 MHz logic clock. Select a divider that meets the PHY's read-return and MDC
limits. MDIO input passes through two synchronization registers and is sampled
at the end of the high phase, allowing most of that phase for PHY return delay.
The PHY launches turnaround acknowledgement on the first released MDC rising
edge, followed by 16 data bits; the final clock drains idle. This follows the
[Linux MDIO bitbang read sequence](https://github.com/torvalds/linux/blob/master/drivers/net/mdio/mdio-bitbang.c).
For example, a 300 ns PHY return delay plus input synchronization fits the default
512 ns high phase at 125 MHz. The minimum divider is a circuit limit, not a
promise that every PHY supports that rate.

All setup fields are snapshotted when COMMAND is accepted. Later writes to
ADDRESS, WRITE_DATA or DIVIDER configure the next transaction. A valid command
submitted while busy returns `CSR_SLVERR` immediately and does not queue or alter
the active frame. COMMAND requires exactly one of its two bits; other selected
bits must be zero. Invalid commands return `CSR_SLVERR`. Writes without byte lane
0 selected are no-ops; unselected bytes are ignored. Other RW and W1C fields honor
byte write strobes normally. COMMAND reads, writes to READ_DATA, and unmapped
addresses return `CSR_DECERR`.

Before a transaction, clear STATUS bits 1 and 2 by writing `6`. Program ADDRESS
and WRITE_DATA if needed, then write COMMAND. Poll BUSY until zero and inspect
DONE and NO_ACK; read READ_DATA for successful reads. DONE is set for both read
and write completions. On reads, the master releases MDIO for both turnaround
bits and the entire data phase; NO_ACK records a high second turnaround bit.
An absent PHY with a pulled-up bus normally produces NO_ACK and read data
`0xffff`. Write transactions have no PHY acknowledgement. Writes preserve the
previous READ_DATA result. New hardware events take priority over W1C clears.

The core leaves MDC low and releases MDIO when idle. A system reset aborts an
active frame, clears status and reasserts PHY reset. PHY_RESET itself is only a
manual output: wait for an idle master before toggling it. Software must supply
the PHY's reset hold/settling delays and program its RGMII timing and negotiation
settings before enabling MAC traffic. No board-specific PHY startup sequence is
hardcoded into the protocol master.

`MdioPins_ifc` splits the bidirectional pad into `mdio_i`, `mdio_o` and `mdio_oe`
(`True` means drive), alongside `mdc`. Connect these to the existing BlueXLNX
`IOBUF_ifc`: drive `o` from `mdio_o`, pass `pack(mdio_oe)` to `oe`, and feed `i`
back into `mdio_i` every logic cycle. Connect `IOBUF.io` to the physical MDIO pad,
`mdc` to MDC, and `phy_reset_n` to the PHY reset pin. The MDIO bus needs its
external pull-up. The library does not instantiate board pads or change PA200T's
top-level wiring.

Clause 45 framing is not implemented. PHY-specific paged registers and indirect
MMD access can be managed by software with ordinary Clause 22 transactions.

Run `make -C hdl/libraries/ethernet/test test-mdio`. The PHY model checks framing,
bit order, all 128 MDC edges, ownership through read turnaround, delayed return
data, missing acknowledgement, divider timing/clamping and snapshotting, busy
and invalid command responses, partial writes, retained read data, W1C flags and
reset during an active frame. The test also elaborates the AXI4-Lite facade into
Verilog and links it with Icarus.
