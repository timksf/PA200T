package TestMdio;

import Clocks      :: *;
import GetPut      :: *;
import StmtFSM     :: *;
import BlueCSRCore :: *;
import Mdio        :: *;
import MdioCsr     :: *;

function Stmt mdio_write(BlueCSR_ifc#(32, 32, 0) csr, Bit#(32) addr, Bit#(32) data, Bit#(4) strb, BlueCSRResponse_t expected);
    return seq
        csr.request.put(BlueCSR_Req_t {wr: True, addr: addr, wdata: data, wstrb: strb, prot: CSR_SECURE});
        action
            let rsp <- csr.response.get;
            if(rsp.resp != expected) begin
                $display("FAIL: MDIO write %h expected %h got %h", addr, pack(expected), pack(rsp.resp));
                $finish(1);
            end
        endaction
    endseq;
endfunction

function Stmt mdio_read(BlueCSR_ifc#(32, 32, 0) csr, Bit#(32) addr, Bit#(32) expected, BlueCSRResponse_t response);
    return seq
        csr.request.put(BlueCSR_Req_t {wr: False, addr: addr, wdata: 0, wstrb: 0, prot: CSR_SECURE});
        action
            let rsp <- csr.response.get;
            if(rsp.resp != response || (response == CSR_OKAY && rsp.rdata != expected)) begin
                $display("FAIL: MDIO read %h expected %h/%h got %h/%h", addr, expected, pack(response), rsp.rdata, pack(rsp.resp));
                $finish(1);
            end
        endaction
    endseq;
endfunction

(* synthesize *)
module mkTestMdio(Empty);
    Clock          clk       <- exposeCurrentClock;
    MakeResetIfc   i_reset   <- mkReset(2, True, clk);
    MdioCsr_ifc    i_dut     <- mkMdioCsr(reset_by i_reset.new_rst);
    PulseWire      w_clear   <- mkPulseWire;
    Reg#(Bit#(32)) rg_cycle  <- mkReg(0);
    Reg#(Bit#(32)) rg_edge   <- mkReg(0);
    Reg#(Bit#(7))  rg_rises  <- mkReg(0);
    Reg#(Bit#(7))  rg_falls  <- mkReg(0);
    Reg#(Bit#(64)) rg_frame  <- mkReg(0);
    Reg#(Bit#(1))  rg_mdc    <- mkReg(0);
    Reg#(Bool)     rg_read   <- mkReg(False);
    Reg#(Bool)     rg_ack    <- mkReg(True);
    Reg#(Bit#(16)) rg_answer <- mkReg('ha55a);
    Reg#(Bit#(16)) rg_period <- mkReg(4);
    Reg#(Bool)     rg_abort  <- mkReg(False);
    Reg#(Bit#(8))  rg_high_age <- mkReg(0);
    Reg#(Bit#(8))  rg_phy_delay <- mkReg(0);

    rule r_clock;
        rg_cycle <= rg_cycle + 1;
        if(rg_cycle == 25000) begin
            $display("FAIL: MDIO timeout");
            $finish(1);
        end
    endrule

    // Model the PHY driving turnaround/data during the high phase. The core
    // must allow return delay and synchronize the input before sampling it.
    rule r_high_age;
        rg_high_age <= i_dut.pins.mdc == 1 ? rg_high_age + 1 : 0;
    endrule

    rule r_phy;
        Bit#(1) value = 1;
        if(rg_read && rg_ack && i_dut.pins.mdc == 1 && rg_high_age >= rg_phy_delay) begin
            if(rg_falls == 46) value = 0;
            else if(rg_falls >= 47 && rg_falls < 63) value = rg_answer[62 - rg_falls];
        end
        i_dut.pins.mdio_i(value);
    endrule

    rule r_monitor;
        let mdc = i_dut.pins.mdc;
        rg_mdc <= mdc;
        if(w_clear) begin
            rg_rises <= 0;
            rg_falls <= 0;
            rg_frame <= 0;
            rg_edge  <= rg_cycle;
        end
        else if(mdc != rg_mdc && !rg_abort) begin
            if(rg_rises != 0 && rg_cycle - rg_edge != zeroExtend(rg_period)) begin
                $display("FAIL: MDIO half-period expected %0d got %0d", rg_period, rg_cycle - rg_edge);
                $finish(1);
            end
            rg_edge <= rg_cycle;
            if(mdc == 1) begin
                if(rg_rises >= 64 || i_dut.pins.mdio_oe != !(rg_read && rg_rises >= 46)) begin
                    $display("FAIL: MDIO ownership/edge count at bit %0d", rg_rises);
                    $finish(1);
                end
                rg_frame <= {rg_frame[62:0], i_dut.pins.mdio_o};
                rg_rises <= rg_rises + 1;
            end
            else rg_falls <= rg_falls + 1;
        end
    endrule

    mkAutoFSM(seq
        delay(8);
        mdio_read(i_dut.csr, 'h00, 0, CSR_OKAY);
        mdio_read(i_dut.csr, 'h0c, 0, CSR_OKAY);
        mdio_read(i_dut.csr, 'h10, 0, CSR_OKAY);
        mdio_read(i_dut.csr, 'h14, 64, CSR_OKAY);
        mdio_read(i_dut.csr, 'h18, 0, CSR_OKAY);
        action
            if(i_dut.phy_reset_n || i_dut.pins.mdio_oe || i_dut.pins.mdc != 0) begin
                $display("FAIL: MDIO reset state");
                $finish(1);
            end
        endaction
        mdio_write(i_dut.csr, 'h18, 1, 1, CSR_OKAY);
        mdio_write(i_dut.csr, 'h00, 'h00001215, 'hf, CSR_OKAY);
        mdio_write(i_dut.csr, 'h04, 'h0000beef, 'hf, CSR_OKAY);
        mdio_write(i_dut.csr, 'h04, 'h0000aa00, 2, CSR_OKAY);
        mdio_read(i_dut.csr, 'h04, 'haaef, CSR_OKAY);
        mdio_write(i_dut.csr, 'h14, 0, 'hf, CSR_OKAY);
        mdio_write(i_dut.csr, 'h08, 0, 'hf, CSR_SLVERR);
        mdio_write(i_dut.csr, 'h08, 3, 'hf, CSR_SLVERR);
        mdio_write(i_dut.csr, 'h08, 'h10001, 'hf, CSR_SLVERR);
        mdio_write(i_dut.csr, 'h08, 2, 0, CSR_OKAY);
        mdio_write(i_dut.csr, 'h08, 2, 2, CSR_OKAY);
        action w_clear.send; endaction
        mdio_write(i_dut.csr, 'h08, 2, 1, CSR_OKAY);
        mdio_read(i_dut.csr, 'h0c, 1, CSR_OKAY);
        mdio_write(i_dut.csr, 'h08, 1, 1, CSR_SLVERR);
        // Writes to setup registers must not alter the active frame or divider.
        mdio_write(i_dut.csr, 'h00, 'h00000102, 'hf, CSR_OKAY);
        mdio_write(i_dut.csr, 'h04, 'h00005555, 'hf, CSR_OKAY);
        mdio_write(i_dut.csr, 'h14, 7, 'hf, CSR_OKAY);
        await(rg_falls == 64);
        delay(4);
        action
            if(rg_frame[63:32] != 'hffffffff || rg_frame[31:30] != 1 || rg_frame[29:28] != 1 ||
                rg_frame[27:23] != 'h12 || rg_frame[22:18] != 'h15 || rg_frame[17:16] != 2 || rg_frame[15:0] != 'haaef ||
                i_dut.pins.mdio_oe || i_dut.pins.mdc != 0) begin
                $display("FAIL: MDIO write frame %h", rg_frame);
                $finish(1);
            end
        endaction
        mdio_read(i_dut.csr, 'h0c, 2, CSR_OKAY);
        mdio_write(i_dut.csr, 'h0c, 2, 2, CSR_OKAY);
        mdio_read(i_dut.csr, 'h0c, 2, CSR_OKAY);
        mdio_write(i_dut.csr, 'h0c, 2, 1, CSR_OKAY);
        mdio_read(i_dut.csr, 'h0c, 0, CSR_OKAY);
        action
            rg_read   <= True;
            rg_period <= 7;
        endaction
        action w_clear.send; endaction
        mdio_write(i_dut.csr, 'h08, 'hffff0001, 1, CSR_OKAY);
        await(rg_falls == 64);
        delay(4);
        action
            if(rg_frame[31:30] != 1 || rg_frame[29:28] != 2 || rg_frame[27:23] != 1 || rg_frame[22:18] != 2) begin
                $display("FAIL: MDIO read header %h", rg_frame);
                $finish(1);
            end
        endaction
        mdio_read(i_dut.csr, 'h0c, 2, CSR_OKAY);
        mdio_read(i_dut.csr, 'h10, 'ha55a, CSR_OKAY);
        mdio_write(i_dut.csr, 'h0c, 6, 1, CSR_OKAY);
        action rg_read <= False; endaction
        action w_clear.send; endaction
        mdio_write(i_dut.csr, 'h04, 'hffff, 3, CSR_OKAY);
        mdio_write(i_dut.csr, 'h08, 2, 'hf, CSR_OKAY);
        await(rg_falls == 64);
        delay(4);
        mdio_read(i_dut.csr, 'h10, 'ha55a, CSR_OKAY);
        action
            if(rg_frame[15:0] != 'hffff) begin
                $display("FAIL: all-one write data");
                $finish(1);
            end
        endaction
        mdio_write(i_dut.csr, 'h0c, 6, 1, CSR_OKAY);
        mdio_write(i_dut.csr, 'h14, 64, 'hf, CSR_OKAY);
        action
            rg_read      <= True;
            rg_period    <= 64;
            rg_phy_delay <= 40;
            rg_answer    <= 'h8001;
        endaction
        action w_clear.send; endaction
        mdio_write(i_dut.csr, 'h08, 1, 'hf, CSR_OKAY);
        await(rg_falls == 64);
        delay(4);
        mdio_read(i_dut.csr, 'h0c, 2, CSR_OKAY);
        mdio_read(i_dut.csr, 'h10, 'h8001, CSR_OKAY);
        mdio_write(i_dut.csr, 'h0c, 6, 1, CSR_OKAY);
        mdio_write(i_dut.csr, 'h14, 7, 'hf, CSR_OKAY);
        action rg_period <= 7; endaction
        action
            rg_ack <= False;
            w_clear.send;
        endaction
        mdio_write(i_dut.csr, 'h08, 1, 'hf, CSR_OKAY);
        await(rg_falls == 64);
        delay(4);
        mdio_read(i_dut.csr, 'h0c, 6, CSR_OKAY);
        mdio_read(i_dut.csr, 'h10, 'hffff, CSR_OKAY);
        mdio_write(i_dut.csr, 'h0c, 6, 1, CSR_OKAY);
        mdio_read(i_dut.csr, 'h0c, 0, CSR_OKAY);
        action
            rg_read <= False;
        endaction
        action w_clear.send; endaction
        mdio_write(i_dut.csr, 'h08, 2, 'hf, CSR_OKAY);
        await(rg_rises == 10);
        action
            rg_abort <= True;
            i_reset.assertReset;
        endaction
        delay(8);
        mdio_read(i_dut.csr, 'h0c, 0, CSR_OKAY);
        mdio_read(i_dut.csr, 'h18, 0, CSR_OKAY);
        action
            if(i_dut.pins.mdc != 0 || i_dut.pins.mdio_oe || i_dut.phy_reset_n) begin
                $display("FAIL: reset did not abort MDIO");
                $finish(1);
            end
        endaction
        mdio_read(i_dut.csr, 'h08, 0, CSR_DECERR);
        mdio_read(i_dut.csr, 'h1c, 0, CSR_DECERR);
        $display("PASS: MDIO Clause 22 framing, turnaround, read data, no-ack, divider, snapshot, strobes, command errors and reset abort");
    endseq);
endmodule

(* synthesize *)
module mkMdioAxiLiteElab(MdioAxiLite_ifc);
    let i_mdio <- mkMdioAxiLite;
    return i_mdio;
endmodule

endpackage
