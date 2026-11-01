package TestUdpTraffic;

import StmtFSM       :: *;
import GetPut        :: *;
import Connectable   :: *;
import AXI4_Stream   :: *;
import BlueCSRCore   :: *;
import EthernetTypes :: *;
import UdpRgmiiCsr   :: *;
import UdpTraffic    :: *;

function Stmt csr_write(BlueCSR_ifc#(32, 32, 0) csr, Bit#(32) addr, Bit#(32) data);
    return seq
        csr.request.put(BlueCSR_Req_t { wr: True, addr: addr, wdata: data, wstrb: 'hf, prot: CSR_SECURE });
        action
            let rsp <- csr.response.get;
            if(rsp.resp != CSR_OKAY) begin
                $display("FAIL: write %h: %h", addr, pack(rsp.resp));
                $finish(1);
            end
        endaction
    endseq;
endfunction

function Stmt csr_read(BlueCSR_ifc#(32, 32, 0) csr, Bit#(32) addr, Reg#(Bit#(32)) result);
    return seq
        csr.request.put(BlueCSR_Req_t { wr: False, addr: addr, wdata: 0, wstrb: 0, prot: CSR_SECURE });
        action
            let rsp <- csr.response.get;
            if(rsp.resp != CSR_OKAY) begin
                $display("FAIL: read %h: %h", addr, pack(rsp.resp));
                $finish(1);
            end
            result <= rsp.rdata;
        endaction
    endseq;
endfunction

function Stmt expect_csr(BlueCSR_ifc#(32, 32, 0) csr, Bit#(32) addr, Bit#(32) expected, Reg#(Bit#(32)) tmp);
    return seq
        csr_read(csr, addr, tmp);
        if(tmp != expected) action
            $display("FAIL: read %h: expected %0d, got %0d", addr, expected, tmp);
            $finish(1);
        endaction
    endseq;
endfunction

(* synthesize *)
module mkTestUdpTraffic(Empty);
    UdpTraffic_ifc        i_dut      <- mkUdpTraffic;
    AXI4_Stream_Rd#(8, 1) i_cap      <- mkAXI4_Stream_Rd(2);
    AXI4_Stream_Wr#(8, 1) i_inj      <- mkAXI4_Stream_Wr(2);

    mkConnection(i_dut.tx_payload, i_cap.fab);
    mkConnection(i_inj.fab, i_dut.rx_payload);

    Reg#(Bool)     rg_loop     <- mkReg(True);
    Reg#(Bit#(16)) rg_port     <- mkReg(7000);
    Reg#(Bit#(32)) rg_seq      <- mkReg(0);
    Reg#(Bit#(16)) rg_index    <- mkReg(0);
    Reg#(Bit#(16)) rg_len      <- mkReg(0);
    Reg#(Bit#(32)) rg_tmp      <- mkReg(0);
    Reg#(Bit#(32)) rg_cycles   <- mkReg(0);
    Reg#(Bit#(16)) rg_echo_len <- mkReg(0);
    Reg#(Bit#(16)) rg_i        <- mkReg(0);

    let csr = i_dut.csr;

    function Bit#(8) expected_byte(Bit#(32) sn, Bit#(16) idx);
        Bit#(8) b = truncate(idx);
        case(idx)
            0: b = sn[31:24];
            1: b = sn[23:16];
            2: b = sn[15:8];
            3: b = sn[7:0];
        endcase
        return b;
    endfunction

    rule r_timeout;
        rg_cycles <= rg_cycles + 1;
        if(rg_cycles == 100000) begin
            $display("FAIL: timeout");
            $finish(1);
        end
    endrule

    // Loopback: every generated packet comes back as a received packet.
    rule r_loop_header(rg_loop);
        let req <- i_dut.tx_header.get;
        UdpRxHeader hdr = unpack(0);
        hdr.dest_port = rg_port;
        hdr.length    = req.payload_length + 8;
        i_dut.rx_header.put(hdr);
        rg_len <= req.payload_length;
    endrule

    rule r_loop_payload(rg_loop);
        let beat <- i_cap.pkg.get;
        if(beat.data != expected_byte(rg_seq, rg_index) || beat.last != (rg_index == rg_len - 1)) begin
            $display("FAIL: generated seq %0d index %0d: ", rg_seq, rg_index, fshow(beat));
            $finish(1);
        end
        rg_index <= beat.last ? 0 : rg_index + 1;
        if(beat.last) rg_seq <= rg_seq + 1;
        i_inj.pkg.put(beat);
    endrule

    function Stmt inject(Bit#(32) sn, Bit#(16) len);
        return seq
            action
                UdpRxHeader hdr = unpack(0);
                hdr.dest_port = 7000;
                hdr.length    = len + 8;
                i_dut.rx_header.put(hdr);
            endaction
            for(rg_i <= 0; rg_i < len; rg_i <= rg_i + 1)
                i_inj.pkg.put(AXI4_Stream_Pkg { data: expected_byte(sn, rg_i), user: 0, keep: 1, dest: 0, id: 0, last: rg_i == len - 1 });
        endseq;
    endfunction

    function Stmt wait_tx_idle();
        return seq
            rg_tmp <= 1;
            while((rg_tmp & 1) != 0) seq
                delay(50);
                csr_read(csr, 'h24, rg_tmp);
            endseq
            delay(20);
        endseq;
    endfunction

    mkAutoFSM(seq
        expect_csr(csr, 'h00, 'h00010000, rg_tmp);
        expect_csr(csr, 'h10, 1472, rg_tmp);

        // 5 packets of 37 bytes through the loopback
        csr_write(csr, 'h10, 37);
        csr_write(csr, 'h14, 5);
        csr_write(csr, 'h04, 1);
        wait_tx_idle;
        expect_csr(csr, 'h28, 5, rg_tmp);
        expect_csr(csr, 'h30, 5, rg_tmp);
        expect_csr(csr, 'h34, 5 * 37, rg_tmp);
        expect_csr(csr, 'h3c, 0, rg_tmp);
        expect_csr(csr, 'h40, 0, rg_tmp);
        expect_csr(csr, 'h44, 0, rg_tmp);
        csr_read(csr, 'h2c, rg_tmp);
        if(rg_tmp < 5 * 37 || rg_tmp > 5 * 39 + 10) action
            $display("FAIL: generator not at one byte per cycle: %0d cycles for %0d bytes", rg_tmp, 5 * 37);
            $finish(1);
        endaction
        $display("generator: %0d bytes in %0d cycles", 5 * 37, rg_tmp);

        // destination port filter
        rg_seq <= 0;
        csr_write(csr, 'h20, 7001);
        csr_write(csr, 'h0c, 1);
        csr_write(csr, 'h14, 3);
        csr_write(csr, 'h04, 1);
        wait_tx_idle;
        expect_csr(csr, 'h30, 0, rg_tmp);
        expect_csr(csr, 'h44, 3, rg_tmp);

        // sequence gap and echo, packets injected by the test
        rg_loop <= False;
        csr_write(csr, 'h20, 0);
        csr_write(csr, 'h0c, 1);
        inject(10, 6);
        inject(12, 9);
        delay(50);
        expect_csr(csr, 'h30, 2, rg_tmp);
        expect_csr(csr, 'h34, 15, rg_tmp);
        expect_csr(csr, 'h3c, 1, rg_tmp);

        csr_write(csr, 'h1c, 1);
        inject('h01020304, 7);
        action
            let req <- i_dut.tx_header.get;
            rg_echo_len <= req.payload_length;
        endaction
        if(rg_echo_len != 7) action
            $display("FAIL: echo header length %0d", rg_echo_len);
            $finish(1);
        endaction
        for(rg_i <= 0; rg_i < 7; rg_i <= rg_i + 1) action
            let beat <- i_cap.pkg.get;
            if(beat.data != expected_byte('h01020304, rg_i) || beat.last != (rg_i == 6)) begin
                $display("FAIL: echo byte %0d: ", rg_i, fshow(beat));
                $finish(1);
            end
        endaction
        expect_csr(csr, 'h30, 3, rg_tmp);

        $display("PASS: UDP traffic generator, counters, port filter and echo");
    endseq);
endmodule

endpackage
