package TestEthernetUdp;

import Clocks         :: *;
import Connectable    :: *;
import DefaultValue   :: *;
import GetPut         :: *;
import StmtFSM        :: *;
import AXI4_Stream    :: *;
import EthernetTypes  :: *;
import EthernetAxisRx :: *;
import EthernetAxisTx :: *;
import UDP            :: *;

(* synthesize *)
module mkTestEthernetUdp(Empty);
    UdpParameters         params        = defaultValue;
    params.arp_request_retry_interval = 500;
    params.arp_request_timeout = 5000;
    let                   i_udp         <- mkUdpComplete(params);
    let                   i_rx          <- mkEthernetAxisRx;
    let                   i_tx          <- mkEthernetAxisTx;
    AXI4_Stream_Wr#(8, 1) i_payload_tx  <- mkAXI4_Stream_Wr(2);
    AXI4_Stream_Rd#(8, 1) i_payload_rx  <- mkAXI4_Stream_Rd(2);

    mkConnection(i_udp.eth_tx_payload, i_tx.payload);
    mkConnection(i_tx.axis,            i_rx.axis);
    mkConnection(i_rx.header,          i_udp.eth_rx);
    mkConnection(i_rx.payload,         i_udp.eth_rx_payload);
    mkConnection(i_payload_tx.fab,     i_udp.udp_tx_payload);
    mkConnection(i_udp.udp_rx_payload, i_payload_rx.fab);

    Reg#(Bit#(16))        rg_cycle      <- mkReg(0);
    Reg#(Bit#(8))         rg_index      <- mkReg(0);
    Reg#(Bit#(8))         rg_length     <- mkReg(4);
    Reg#(Bit#(8))         rg_packet     <- mkReg(0);
    Reg#(Bit#(16))        rg_arp_frames <- mkReg(0);

    rule r_configure;
        i_udp.configure(EthernetConfig {
            local_mac:   'h021122334455,
            local_ip:    'hc0a80164,
            gateway_ip:  'hc0a80101,
            subnet_mask: 'hffffff00
        }, False);
        rg_cycle <= rg_cycle + 1;
        if(rg_cycle == 15000) begin
            $display("FAIL: UDP loopback timeout, ARP frames = %0d", rg_arp_frames);
            $finish(1);
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
        if(hdr.eth_type == 'h0806) rg_arp_frames <= rg_arp_frames + 1;
    endrule

    mkAutoFSM(seq
        delay(10);
        for(rg_packet <= 0; rg_packet < 2; rg_packet <= rg_packet + 1) seq
            action
                i_udp.udp_tx.put(UdpTxHeader {
                    ip_dscp:      0,
                    ip_ecn:       0,
                    ip_ttl:       64,
                    ip_source_ip: 'hc0a80164,
                    ip_dest_ip:   'hc0a80164,
                    source_port:  1234,
                    dest_port:    5678,
                    length:       zeroExtend(rg_length) + 8,
                    checksum:     0
                });
            endaction
            for(rg_index <= 0; rg_index < rg_length; rg_index <= rg_index + 1)
                i_payload_tx.pkg.put(AXI4_Stream_Pkg {
                    data: rg_index ^ 'ha5,
                    user: 0,
                    keep: 1,
                    dest: 0,
                    id:   0,
                    last: rg_index == rg_length - 1
                });
            delay(200);
            action
                let hdr <- i_udp.udp_rx.get;
                if(hdr.eth_src_mac != 'h021122334455 || hdr.eth_dest_mac != 'h021122334455 ||
                    hdr.ip_source_ip != 'hc0a80164 || hdr.ip_dest_ip != 'hc0a80164 ||
                    hdr.source_port != 1234 || hdr.dest_port != 5678 ||
                    hdr.length != zeroExtend(rg_length) + 8 || hdr.checksum == 0) begin
                    $display("FAIL: UDP received header: ", fshow(hdr));
                    $finish(1);
                end
            endaction
            for(rg_index <= 0; rg_index < rg_length; rg_index <= rg_index + 1) seq
                delay(3);
                action
                    let beat <- i_payload_rx.pkg.get;
                    if(beat.data != (rg_index ^ 'ha5) || beat.user != 0 || beat.keep != 1 ||
                        beat.last != (rg_index == rg_length - 1) || beat.dest != 0 || beat.id != 0) begin
                        $display("FAIL: UDP received payload index %0d: ", rg_index, fshow(beat));
                        $finish(1);
                    end
                endaction
            endseq
            rg_length <= 37;
        endseq
        action
            if(rg_arp_frames == 0) begin
                $display("FAIL: no ARP exchange observed");
                $finish(1);
            end
        endaction
        $display("PASS: UDP Ethernet loopback, ARP resolution, checksum generation and RX backpressure");
    endseq);
endmodule

endpackage
