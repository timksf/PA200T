package TestEthernetRegs;

import StmtFSM       :: *;
import GetPut        :: *;
import BlueCSRCore   :: *;
import EthernetRegs  :: *;
import EthernetTypes :: *;
import UDP           :: *;
import RgmiiMac      :: *;
import Mdio          :: *;

function Stmt csr_write(BlueCSR_ifc#(32, 32, 0) csr, Bit#(32) addr, Bit#(32) data, Bit#(4) strb);
    return seq
        csr.request.put(BlueCSR_Req_t {
            wr:    True,
            addr:  addr,
            wdata: data,
            wstrb: strb,
            prot:  CSR_SECURE
        });
        action
            let rsp <- csr.response.get;
            if(rsp.resp != CSR_OKAY) begin
                $display("FAIL: write %h: %h", addr, pack(rsp.resp));
                $finish(1);
            end
        endaction
    endseq;
endfunction

function Stmt expect_read(BlueCSR_ifc#(32, 32, 0) csr, Bit#(32) addr, Bit#(32) expected, BlueCSRResponse_t response);
    return seq
        csr.request.put(BlueCSR_Req_t {
            wr:    False,
            addr:  addr,
            wdata: 0,
            wstrb: 0,
            prot:  CSR_SECURE
        });
        action
            let rsp <- csr.response.get;
            if(rsp.resp != response || (response == CSR_OKAY && rsp.rdata != expected)) begin
                $display("FAIL: read %h: expected %h/%h, got %h/%h", addr, expected, pack(response), rsp.rdata, pack(rsp.resp));
                $finish(1);
            end
        endaction
    endseq;
endfunction

(* synthesize *)
module mkTestEthernetRegs(Empty);
    BlueCSRAccess_ifc#(32, 32, 0, EthernetRegs_ifc) i_csrs         <- create_blue_csr(ethernet_csrs, False);
    Reg#(Bool)                                      rg_event       <- mkReg(False);
    Reg#(Bit#(8))                                   rg_clear_count <- mkReg(0);
    Reg#(Bit#(16))                                  rg_cycles      <- mkReg(0);

    rule r_timeout;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 2000) begin
            $display("FAIL: CSR timeout");
            $finish(1);
        end
    endrule

    rule r_mdio_idle;
        i_csrs.internal.mdio.mdio_i(1);
    endrule

    rule r_observe;
        UdpStatus      udp = unpack(0);
        RgmiiMacStatus mac = unpack(0);
        udp.ip_rx_busy = True;
        udp.ip_rx_error_invalid_header = rg_event;
        mac.speed = 2;
        mac.rx_error_bad_fcs = rg_event;
        i_csrs.internal.observe(udp, mac, rg_event);
        if(i_csrs.internal.clear_arp_cache) rg_clear_count <= rg_clear_count + 1;
    endrule

    mkAutoFSM(seq
        delay(5);
        expect_read(i_csrs.external, 'h00, 'h00010000, CSR_OKAY);
        expect_read(i_csrs.external, 'h04, 'h00000c00, CSR_OKAY);
        csr_write(i_csrs.external, 'h08, 'h33445566, 'hf);
        csr_write(i_csrs.external, 'h0c, 'h00000211, 'hf);
        csr_write(i_csrs.external, 'h10, 'hc0a80164, 'hf);
        csr_write(i_csrs.external, 'h14, 'hc0a80101, 'hf);
        csr_write(i_csrs.external, 'h18, 'hffffff00, 'hf);
        csr_write(i_csrs.external, 'h1c, 'hc0a80165, 'hf);
        csr_write(i_csrs.external, 'h20, 'hbeef1234, 'hf);
        csr_write(i_csrs.external, 'h24, 'h0000a580, 'hf);
        csr_write(i_csrs.external, 'h04, 3, 1);
        expect_read(i_csrs.external, 'h04, 'h00000c03, CSR_OKAY);
        csr_write(i_csrs.external, 'h08, 'h0000aa00, 2);
        expect_read(i_csrs.external, 'h08, 'h3344aa66, CSR_OKAY);
        action
            let cfg = i_csrs.internal.network;
            let hdr = i_csrs.internal.tx_header(12, 'h5678);
            if(cfg.local_mac != 'h02113344aa66 || cfg.local_ip != 'hc0a80164 ||
                cfg.gateway_ip != 'hc0a80101 || cfg.subnet_mask != 'hffffff00 ||
                hdr.ip_source_ip != cfg.local_ip || hdr.ip_dest_ip != 'hc0a80165 ||
                hdr.source_port != 'h1234 || hdr.dest_port != 'hbeef || hdr.ip_ttl != 'h80 ||
                hdr.ip_dscp != 'h25 || hdr.ip_ecn != 2 || hdr.length != 12 || hdr.checksum != 'h5678 ||
                !i_csrs.internal.tx_enable || !i_csrs.internal.rx_enable) begin
                $display("FAIL: CSR hardware configuration");
                $finish(1);
            end
        endaction
        expect_read(i_csrs.external, 'h2c, 'h00000102, CSR_OKAY);
        csr_write(i_csrs.external, 'h28, 1, 1);
        delay(5);
        action
            if(rg_clear_count != 1 || i_csrs.internal.clear_arp_cache) begin
                $display("FAIL: ARP clear pulse");
                $finish(1);
            end
        endaction
        rg_event <= True;
        delay(3);
        rg_event <= False;
        expect_read(i_csrs.external, 'h30, 'h204, CSR_OKAY);
        expect_read(i_csrs.external, 'h34, 'h20, CSR_OKAY);
        csr_write(i_csrs.external, 'h30, 4, 1);
        expect_read(i_csrs.external, 'h30, 'h200, CSR_OKAY);
        csr_write(i_csrs.external, 'h30, 'h200, 1);
        expect_read(i_csrs.external, 'h30, 'h200, CSR_OKAY);
        csr_write(i_csrs.external, 'h30, 'h200, 2);
        expect_read(i_csrs.external, 'h30, 0, CSR_OKAY);
        rg_event <= True;
        csr_write(i_csrs.external, 'h34, 'h20, 1);
        rg_event <= False;
        expect_read(i_csrs.external, 'h34, 'h20, CSR_OKAY);
        csr_write(i_csrs.external, 'h34, 'h20, 1);
        expect_read(i_csrs.external, 'h34, 0, CSR_OKAY);
        expect_read(i_csrs.external, 'h54, 64, CSR_OKAY);
        expect_read(i_csrs.external, 'h58, 0, CSR_OKAY);
        csr_write(i_csrs.external, 'h58, 1, 1);
        action
            if(!i_csrs.internal.phy_reset_n) begin
                $display("FAIL: unified MDIO PHY reset");
                $finish(1);
            end
        endaction
        expect_read(i_csrs.external, 'hfc, 0, CSR_DECERR);
        $display("PASS: Ethernet CSR defaults, strobes, configuration, pulse and sticky events");
    endseq);
endmodule

endpackage
