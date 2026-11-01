package TestUdpTrafficStack;

import Connectable    :: *;
import DefaultValue   :: *;
import GetPut         :: *;
import StmtFSM        :: *;
import AXI4_Stream    :: *;
import BlueCSRCore    :: *;
import EthernetTypes  :: *;
import EthernetAxisRx :: *;
import EthernetAxisTx :: *;
import UDP            :: *;
import UdpRgmiiCsr    :: *;
import UdpTraffic     :: *;

// Generator -> udp_complete -> Ethernet loopback -> udp_complete -> counters.
// The loopback idles 20 byte times after each frame like a MAC
// (preamble, FCS, IFG), so the stack sees line-rate back pressure.
(* synthesize *)
module mkTestUdpTrafficStack(Empty);
    UdpParameters         params    = defaultValue;
    params.arp_request_retry_interval = 500;
    params.arp_request_timeout        = 5000;
    let                   i_udp     <- mkUdpComplete(params);
    let                   i_rx      <- mkEthernetAxisRx;
    let                   i_tx      <- mkEthernetAxisTx;
    UdpTraffic_ifc        i_traffic <- mkUdpTraffic;
    AXI4_Stream_Rd#(8, 1) i_wire_in <- mkAXI4_Stream_Rd(2);
    AXI4_Stream_Wr#(8, 1) i_wire_out <- mkAXI4_Stream_Wr(2);

    Bit#(32) ip = 'hc0a80164;

    mkConnection(i_udp.eth_tx_payload, i_tx.payload);
    mkConnection(i_tx.axis,            i_wire_in.fab);
    mkConnection(i_wire_out.fab,       i_rx.axis);
    mkConnection(i_rx.header,          i_udp.eth_rx);
    mkConnection(i_rx.payload,         i_udp.eth_rx_payload);
    mkConnection(i_traffic.tx_payload, i_udp.udp_tx_payload);
    mkConnection(i_udp.udp_rx_payload, i_traffic.rx_payload);

    Reg#(Bit#(32)) rg_cycle   <- mkReg(0);
    Reg#(Bit#(8))  rg_idle    <- mkReg(0);
    Reg#(Bit#(32)) rg_errors  <- mkReg(0);
    Reg#(Bit#(32)) rg_tmp     <- mkReg(0);
    Reg#(Bit#(32)) rg_frames  <- mkReg(0);
    Reg#(Bit#(32)) rg_arp     <- mkReg(0);
    Reg#(Bit#(32)) rg_udp_hdr <- mkReg(0);
    Reg#(Bit#(32)) rg_eth_hdr <- mkReg(0);

    rule r_rx_header;
        let hdr <- i_udp.udp_rx.get;
        rg_udp_hdr <= rg_udp_hdr + 1;
        i_traffic.rx_header.put(hdr);
    endrule

    let csr = i_traffic.csr;

    rule r_configure;
        i_udp.configure(EthernetConfig {
            local_mac:   'h021122334455,
            local_ip:    ip,
            gateway_ip:  'hc0a80101,
            subnet_mask: 'hffffff00
        }, False);
        rg_cycle <= rg_cycle + 1;
        if(rg_cycle == 3000000) begin
            $display("FAIL: timeout");
            $finish(1);
        end
    endrule

    rule r_errors;
        let s = i_udp.status;
        if(s.ip_rx_error_header_early_termination || s.ip_rx_error_invalid_header || s.ip_rx_error_invalid_checksum || s.udp_rx_error_header_early_termination || i_rx.error_header_early_termination || s.ip_tx_error_payload_early_termination || s.udp_tx_error_payload_early_termination ||
           s.ip_rx_error_payload_early_termination || s.udp_rx_error_payload_early_termination ||
           s.ip_tx_error_arp_failed) begin
            rg_errors <= rg_errors + 1;
            $display("%0d: protocol error ", rg_cycle, fshow(s));
        end
    endrule

    rule r_drop_ip;
        let hdr <- i_udp.ip_rx.get;
    endrule
    rule r_idle_ip;
        i_udp.ip_rx_payload.ptready(True);
        i_udp.ip_tx_payload.ptvalid(False);
        i_udp.ip_tx_payload.ptdata(0);
        i_udp.ip_tx_payload.ptlast(False);
        i_udp.ip_tx_payload.ptuser(0);
        i_udp.ip_tx_payload.ptkeep(1);
        i_udp.ip_tx_payload.ptDest(0);
        i_udp.ip_tx_payload.ptid(0);
    endrule

    rule r_forward_header;
        let hdr <- i_udp.eth_tx.get;
        i_tx.header.put(hdr);
        if(hdr.eth_type == 'h0806) rg_arp <= rg_arp + 1; else rg_eth_hdr <= rg_eth_hdr + 1;
    endrule

    rule r_tx_header;
        let req <- i_traffic.tx_header.get;
        i_udp.udp_tx.put(UdpTxHeader {
            ip_dscp: 0, ip_ecn: 0, ip_ttl: 64,
            ip_source_ip: ip, ip_dest_ip: ip,
            source_port: 1234, dest_port: 5678,
            length: req.payload_length + 8, checksum: 0
        });
    endrule

    rule r_wire(rg_idle == 0);
        let beat <- i_wire_in.pkg.get;
        i_wire_out.pkg.put(beat);
        if(beat.last) begin rg_idle <= 20; rg_frames <= rg_frames + 1; end
    endrule

    rule r_wire_gap(rg_idle != 0);
        rg_idle <= rg_idle - 1;
    endrule

    function Stmt csr_write(Bit#(32) addr, Bit#(32) data) = seq
        csr.request.put(BlueCSR_Req_t { wr: True, addr: addr, wdata: data, wstrb: 'hf, prot: CSR_SECURE });
        action let rsp <- csr.response.get; endaction
    endseq;

    function Stmt csr_read(Bit#(32) addr) = seq
        csr.request.put(BlueCSR_Req_t { wr: False, addr: addr, wdata: 0, wstrb: 0, prot: CSR_SECURE });
        action let rsp <- csr.response.get; rg_tmp <= rsp.rdata; endaction
    endseq;

    function Stmt run(Bit#(16) length, Bit#(32) count) = seq
        csr_write('h0c, 1);
        csr_write('h10, zeroExtend(length));
        csr_write('h14, count);
        csr_write('h04, 1);
        rg_tmp <= 1;
        while(rg_tmp != 0) seq
            delay(200);
            csr_read('h24);
        endseq
        delay(3000);
        csr_read('h30);
        $display("length %0d: %0d of %0d packets received, %0d protocol errors so far", length, rg_tmp, count, rg_errors);
        $display("  eth tx ip headers %0d, arp %0d, wire frames %0d, udp rx headers %0d", rg_eth_hdr, rg_arp, rg_frames, rg_udp_hdr);
        csr_read('h28); $display("  TX_PACKETS %0d", rg_tmp);
        csr_read('h44); $display("  RX_IGNORED %0d", rg_tmp);
        csr_read('h40); $display("  RX_BAD %0d", rg_tmp);
        csr_read('h30);
        if(rg_tmp != count) action
            $display("FAIL: lost packets at length %0d", length);
            $finish(1);
        endaction
        csr_read('h3c);
        if(rg_tmp != 0) action
            $display("FAIL: %0d sequence errors at length %0d", rg_tmp, length);
            $finish(1);
        endaction
    endseq;

    mkAutoFSM(seq
        delay(10);
        run(1472, 4);
        run(64, 300);
        run(18, 300);
        run(256, 100);
        run(1472, 20);
        if(rg_errors != 0) action
            $display("FAIL: %0d protocol errors", rg_errors);
            $finish(1);
        endaction
        $display("PASS: UDP traffic through udp_complete at line rate, 18 to 1472 byte payloads");
    endseq);
endmodule

endpackage
