package UdpRgmii;

import Clocks         :: *;
import Connectable    :: *;
import GetPut         :: *;
import AXI4_Stream    :: *;
import EthernetTypes  :: *;
import EthernetAxisRx :: *;
import EthernetAxisTx :: *;
import UDP            :: *;
import RgmiiMac       :: *;

interface UdpRgmii_ifc;
    interface Put#(UdpTxHeader)        tx_header;
    interface EthernetStreamSink_ifc   tx_payload;
    interface Get#(UdpRxHeader)        rx_header;
    interface EthernetStreamSource_ifc rx_payload;
    interface RgmiiPins_ifc            pins;

    (* always_ready, always_enabled *)
    method Action         configure(EthernetConfig cfg, Bool clear_cache, Bit#(8) ifg, Bool tx_enable, Bool rx_enable);
    method UdpStatus      udp_status;
    method RgmiiMacStatus mac_status;
    method Bool           rx_header_error;
endinterface

module mkUdpRgmii#(
    UdpParameters      udp_params,
    RgmiiMacParameters mac_params,
    Clock              gtx_clk,
    Clock              gtx_clk90,
    Reset              gtx_rst_n,
    Clock              rgmii_rx_clk
)(UdpRgmii_ifc);

    let i_udp <- mkUdpComplete(udp_params);
    let i_rx  <- mkEthernetAxisRx;
    let i_tx  <- mkEthernetAxisTx;
    let i_mac <- mkRgmiiMac(mac_params, gtx_clk, gtx_clk90, gtx_rst_n, rgmii_rx_clk);

    mkConnection(i_mac.rx,             i_rx.axis);
    mkConnection(i_rx.header,          i_udp.eth_rx);
    mkConnection(i_rx.payload,         i_udp.eth_rx_payload);
    mkConnection(i_udp.eth_tx,         i_tx.header);
    mkConnection(i_udp.eth_tx_payload, i_tx.payload);
    mkConnection(i_tx.axis,            i_mac.tx);

    // Unhandled non-UDP IPv4 traffic must drain to avoid blocking later frames.
    rule r_drop_ip_header;
        let hdr <- i_udp.ip_rx.get;
    endrule

    rule r_drop_ip_payload;
        i_udp.ip_rx_payload.ptready(True);
    endrule

    rule r_idle_ip_transmit;
        i_udp.ip_tx_payload.ptvalid(False);
        i_udp.ip_tx_payload.ptdata(0);
        i_udp.ip_tx_payload.ptlast(False);
        i_udp.ip_tx_payload.ptuser(0);
        i_udp.ip_tx_payload.ptkeep(1);
        i_udp.ip_tx_payload.ptDest(0);
        i_udp.ip_tx_payload.ptid(0);
    endrule

    interface tx_header  = i_udp.udp_tx;
    interface tx_payload = i_udp.udp_tx_payload;
    interface rx_header  = i_udp.udp_rx;
    interface rx_payload = i_udp.udp_rx_payload;
    interface pins       = i_mac.pins;

    method Action configure(EthernetConfig cfg, Bool clear_cache, Bit#(8) ifg, Bool tx_enable, Bool rx_enable);
        i_udp.configure(cfg, clear_cache);
        i_mac.configure(ifg, tx_enable, rx_enable);
    endmethod
    method udp_status      = i_udp.status;
    method mac_status      = i_mac.status;
    method rx_header_error = i_rx.error_header_early_termination;
endmodule

endpackage
