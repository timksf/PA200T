package UdpRgmiiCsr;

import Clocks                 :: *;
import GetPut                 :: *;
import AXI4_Lite_Slave        :: *;
import BlueCSRCore            :: *;
import BlueCSRAXI4LiteAdapter :: *;
import EthernetTypes          :: *;
import EthernetRegs           :: *;
import UDP                    :: *;
import RgmiiMac               :: *;
import UdpRgmii               :: *;
import Mdio                   :: *;

// The CSR endpoint supplies addresses, ports and IPv4 options at header acceptance.
typedef struct {
    Bit#(16) payload_length;
    Bit#(16) checksum;
} UdpTxRequest deriving(Bits, Eq, FShow);

interface UdpRgmiiCsr_ifc;
    interface BlueCSR_ifc#(32, 32, 0)  csr;
    interface Put#(UdpTxRequest)       tx_header;
    interface EthernetStreamSink_ifc   tx_payload;
    interface Get#(UdpRxHeader)        rx_header;
    interface EthernetStreamSource_ifc rx_payload;
    interface RgmiiPins_ifc            pins;
    interface MdioPins_ifc             mdio;
    method Bool                       phy_reset_n;
endinterface

module [Module] mkUdpRgmiiCsr#(
    UdpParameters      udp_params,
    RgmiiMacParameters mac_params,
    Clock              gtx_clk,
    Clock              gtx_clk90,
    Reset              gtx_rst_n,
    Clock              rgmii_rx_clk
)(UdpRgmiiCsr_ifc);

    BlueCSRAccess_ifc#(32, 32, 0, EthernetRegs_ifc) i_csrs <- create_blue_csr(ethernet_csrs, False);
    let                                             i_eth  <- mkUdpRgmii(udp_params, mac_params, gtx_clk, gtx_clk90, gtx_rst_n, rgmii_rx_clk);

    rule r_configure;
        i_eth.configure(i_csrs.internal.network, i_csrs.internal.clear_arp_cache,
            i_csrs.internal.ifg, i_csrs.internal.tx_enable, i_csrs.internal.rx_enable);
    endrule

    rule r_observe;
        i_csrs.internal.observe(i_eth.udp_status, i_eth.mac_status, i_eth.rx_header_error);
    endrule

    interface Put tx_header;
        method Action put(UdpTxRequest req) if(i_csrs.internal.tx_enable);
            i_eth.tx_header.put(i_csrs.internal.tx_header(req.payload_length + 8, req.checksum));
        endmethod
    endinterface
    interface csr        = i_csrs.external;
    interface tx_payload = i_eth.tx_payload;
    interface rx_header  = i_eth.rx_header;
    interface rx_payload = i_eth.rx_payload;
    interface pins       = i_eth.pins;
    interface mdio       = i_csrs.internal.mdio;
    method phy_reset_n   = i_csrs.internal.phy_reset_n;
endmodule

interface UdpRgmiiAxiLite_ifc;
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_wr;
    interface Put#(UdpTxRequest)              tx_header;
    interface EthernetStreamSink_ifc          tx_payload;
    interface Get#(UdpRxHeader)               rx_header;
    interface EthernetStreamSource_ifc        rx_payload;
    interface RgmiiPins_ifc                   pins;
    interface MdioPins_ifc                    mdio;
    method Bool                              phy_reset_n;
endinterface

module [Module] mkUdpRgmiiAxiLite#(
    UdpParameters      udp_params,
    RgmiiMacParameters mac_params,
    Clock              gtx_clk,
    Clock              gtx_clk90,
    Reset              gtx_rst_n,
    Clock              rgmii_rx_clk
)(UdpRgmiiAxiLite_ifc);

    let i_eth <- mkUdpRgmiiCsr(udp_params, mac_params, gtx_clk, gtx_clk90, gtx_rst_n, rgmii_rx_clk);
    let i_axi <- mkBlueCSRAXI4LiteAdapter(i_eth.csr, 1, 1);

    interface s_rd       = i_axi.s_rd;
    interface s_wr       = i_axi.s_wr;
    interface tx_header  = i_eth.tx_header;
    interface tx_payload = i_eth.tx_payload;
    interface rx_header  = i_eth.rx_header;
    interface rx_payload = i_eth.rx_payload;
    interface pins       = i_eth.pins;
    interface mdio       = i_eth.mdio;
    method phy_reset_n   = i_eth.phy_reset_n;
endmodule

endpackage
