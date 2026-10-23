# Ethernet UDP library

BVI wrappers for the checked-in `dep/verilog-ethernet` RTL:

| Package / constructor | RTL / role |
| --- | --- |
| `UDP::mkUdpComplete` | `udp_complete`: UDP, IPv4 and ARP; also exposes the raw IPv4 path |
| `EthernetAxisRx::mkEthernetAxisRx` | `eth_axis_rx`: split Ethernet headers from a frame stream |
| `EthernetAxisTx::mkEthernetAxisTx` | `eth_axis_tx`: combine Ethernet headers and payload |
| `RgmiiMac::mkRgmiiMac` | `eth_mac_1g_rgmii_fifo`: RGMII MAC with asynchronous TX/RX frame FIFOs |
| `UdpRgmii::mkUdpRgmii` | Connect all four blocks; drain non-UDP IPv4 traffic |
| `UdpRgmiiCsr::mkUdpRgmiiCsr` | Complete endpoint with one native `BlueCSR_ifc#(32, 32, 0)` register file |
| `UdpRgmiiCsr::mkUdpRgmiiAxiLite` | Same endpoint and register file through BlueCSR's BlueAXI AXI4-Lite adapter |
| `Mdio::mkMdioMaster` | Native Bluespec Clause 22 master with request/response interfaces |
| `MdioCsr::mkMdioCsr` / `mkMdioAxiLite` | Standalone BlueCSR / AXI4-Lite MDIO controller |

Import `Ethernet::*` for the public library. Interface types use the `_ifc`
suffix, including `UdpRgmiiCsr_ifc`, `UdpRgmiiAxiLite_ifc` and `RgmiiPins_ifc`. `Ethernet.mk` adds the BSV search
paths, BlueAXI/BlueCSR dependencies, and upstream Verilog directories to BSVTools.
The wrapper library does not instantiate the endpoint in `PA200T` or assign board
pins, clocks, or board-specific timing constraints. MDIO and manual PHY reset are
exposed through the unified CSR endpoint; see [MDIO](MDIO.md) for its register map
and pad connections.

## Interfaces and clocking

Payloads use the existing BlueAXI interfaces directly:
`AXI4_Stream_Rd_Fab#(8, 1)` for a sink and
`AXI4_Stream_Wr_Fab#(8, 1)` for a source. Connect with `mkConnection` to native
BlueAXI stream adapters. Every beat is one byte: supply `keep = 1`, `dest = 0`,
`id = 0`. Output sidebands have those values. `last` terminates the packet and
`user[0]` marks an invalid frame. No private replacement AXI interface is needed
at the boundary.

Headers use typed `Get`/`Put`. Each header transfer is independent of payload
transfers; send one header before its payload, keep data stable under backpressure,
and consume both the receive header and payload to let subsequent traffic proceed.
The individual wrappers expose complete upstream header metadata.

The default BSV clock/reset drive all application streams, CSRs and UDP/IP/ARP
logic. Resets supplied to public constructors are conventional active-low BSV
resets; wrappers invert them for the upstream active-high RTL inputs. Supply:

- `gtx_clk`: 125 MHz MAC reference clock.
- `gtx_clk90`: the same clock shifted by 90 degrees when `use_clk90 = "TRUE"`.
- `gtx_rst_n`: a reset associated with `gtx_clk`.
- `rgmii_rx_clk`: the clock from the PHY. `pins.rx_data` belongs to this domain.

`pins.tx_clk`, `pins.tx_data` and `pins.tx_ctl` drive the PHY. The MAC's asynchronous
frame FIFOs cross into the application clock domain. Size them and choose the
application clock for the required traffic rate; sustained 1 Gb/s byte streams
require 125 MHz throughput. Default primitive settings target Artix-7:
`XILINX`, `IODDR`, `BUFR`, and shifted TX clock enabled. Choose TX clock delay to
match the PHY configuration and board timing; avoid adding the same delay twice.
Use `target = "GENERIC"` for portable RTL simulation.

The upstream Vivado constraint scripts are in
`dep/verilog-ethernet/syn/vivado/`. Integrating a board still requires its PHY
clock/delay constraints and pin assignments.

## Unified CSR endpoint

`mkUdpRgmiiCsr` and `mkUdpRgmiiAxiLite` use the **same** `ethernet_csrs` definition.
The AXI4-Lite version exposes `s_rd` and `s_wr`, matching the existing BlueAXI and
BlueFabric control-bus conventions. The native CSR version can be connected to a
BlueCSR mux or the existing APB adapter instead.

The TX request is `UdpTxRequest { payload_length, checksum }`. Addresses, UDP
ports, TTL, DSCP and ECN are read from the unified register file when the header
is accepted; `payload_length + 8` becomes the UDP length. With default checksum
generation enabled, the RTL computes the UDP checksum from the payload, including
odd lengths; `checksum` is used when generation is disabled. Supply exactly
`payload_length` bytes and assert `last` on the final byte. Use nonempty packets
within the configured FIFO capacities and network MTU (up to 1472 payload bytes
for a standard 1500-byte IPv4 MTU). The upstream checksum generator buffers a
whole packet, so its payload FIFO must fit that packet.

Receive metadata retains all received addresses and ports. Transmit port settings
do not filter received UDP packets: applications select packets using the RX
header. The upstream receiver exposes the UDP checksum without validating it.
Remote MAC addresses are resolved by ARP rather than programmed as static peers.

All offsets below are byte offsets. Registers support BlueCSR byte write strobes.
IPv4 values are numeric network-order addresses: `192.168.1.100 = 0xc0a80164`.
For MAC `02:11:22:33:44:55`, write `MAC_HIGH = 0x0211` and
`MAC_LOW = 0x22334455`.

| Offset | Register | Fields / reset |
| --- | --- | --- |
| `0x00` | VERSION, RO | `0x00010000` |
| `0x04` | CONTROL, RW | TX enable bit 0 = 0; RX enable bit 1 = 0; IFG bits 15:8 = 12 |
| `0x08` | MAC_LOW, RW | Local MAC bits 31:0 = 0 |
| `0x0c` | MAC_HIGH, RW | Local MAC bits 47:32 in bits 15:0 = 0 |
| `0x10` | LOCAL_IP, RW | Local IPv4 address = 0 |
| `0x14` | GATEWAY_IP, RW | IPv4 gateway = 0 |
| `0x18` | SUBNET_MASK, RW | IPv4 subnet mask = 0 |
| `0x1c` | PEER_IP, RW | Transmit destination IPv4 address = 0 |
| `0x20` | UDP_PORTS, RW | Source bits 15:0 = 0; destination bits 31:16 = 0 |
| `0x24` | IP_OPTIONS, RW | TTL bits 7:0 = 64; DSCP bits 13:8 = 0; ECN bits 15:14 = 0 |
| `0x28` | ARP_CLEAR, WO | Any successful write generates one clear pulse |
| `0x2c` | STATUS, RO | Speed bits 1:0; IP RX/TX busy bits 8/9; UDP RX/TX busy bits 10/11 |
| `0x30` | PROTOCOL_EVENTS, W1C | Sticky events listed below, reset 0 |
| `0x34` | MAC_EVENTS, W1C | Sticky events listed below, reset 0 |
| `0x40`–`0x58` | MDIO | PHY/register addresses, command/data/status, divider and PHY reset; see [MDIO](MDIO.md) |

STATUS reports sampled hardware values. Speed is clock detection (`0`: 10M,
`1`: 100M, `2`: 1G), not PHY link-up status. A new event takes priority over a
simultaneous software clear. Unmapped accesses and unsupported access directions
return `CSR_DECERR` (AXI4-Lite `DECERR`).

| Bit | PROTOCOL_EVENTS | MAC_EVENTS |
| --- | --- | --- |
| 0 | IP RX header early termination | TX underflow |
| 1 | IP RX payload early termination | TX FIFO overflow |
| 2 | IP RX invalid header | TX FIFO bad frame |
| 3 | IP RX invalid checksum | TX FIFO good frame |
| 4 | IP TX payload early termination | RX bad frame |
| 5 | IP TX ARP resolution failed | RX bad FCS |
| 6 | UDP RX header early termination | RX FIFO overflow |
| 7 | UDP RX payload early termination | RX FIFO bad frame |
| 8 | UDP TX payload early termination | RX FIFO good frame |
| 9 | Ethernet RX header early termination | Reserved |

Release PHY reset, wait for PHY settling and configure its RGMII timing/link via
MDIO before enabling traffic. Program addresses and options with MAC TX/RX disabled, clear the ARP cache, then
write `CONTROL = 0x00000c03` to enable both directions with the standard IFG.
For reconfiguration, stop new application traffic and drain outstanding packets
before disabling the MAC and changing settings. Register writes take effect
individually. MAC configuration must remain stable during traffic, as required
by the upstream MAC's clock-domain interface.

ARP cache size, retry timing, checksum generation, FIFO depths and primitive
selection remain elaboration parameters (`UdpParameters`, `RgmiiMacParameters`)
because the upstream RTL implements them as Verilog parameters. The default ARP
intervals assume a 125 MHz application clock; adjust their cycle counts when
using another rate.

## Validation

Run `make -C hdl/libraries/ethernet/test test` with `bsc`, a C++ compiler and
Icarus Verilog installed. Build products and logs stay under `test/build`.

The tests cover CSR defaults, partial writes, configuration outputs, ARP clear,
sticky-event priority/W1C, invalid addresses; UDP/ARP Ethernet loopback with
checksum generation, odd/even payloads and receive backpressure; and the complete
AXI4-Lite-configured endpoint through RGMII loopback with different application
and GTX clock rates; and native MDIO pin-level framing, delayed reads, no-ack,
command/strobe handling, divider behavior and reset abort. The RGMII test uses
generic DDR simulation models. These
checks do not replace board timing closure or PHY validation.
