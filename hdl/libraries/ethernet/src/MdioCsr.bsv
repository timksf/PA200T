package MdioCsr;

import GetPut                 :: *;

import BlueCSRCore            :: *;
import BlueCSRAXI4LiteAdapter :: *;
import AXI4_Lite_Slave        :: *;
import Mdio                   :: *;

interface MdioControl_ifc;
    interface MdioPins_ifc pins;
    method Bool           phy_reset_n;
endinterface

// Composable register block; the enclosing peripheral owns csr_regmap_def.
module [BlueCSRCtx_t#(32, 32)] mdio_csrs(MdioControl_ifc);
    MdioMaster_ifc i_mdio         <- mkMdioMaster;
    Wire#(Bool)    w_done         <- mkDWire(False);
    Wire#(Bool)    w_no_ack       <- mkDWire(False);

    csr_reg_def('h00, "MDIO_ADDRESS", "Clause 22 PHY and register addresses");
    Reg#(Bit#(5))  rg_reg_addr    <- csr_reg_rw('h00, 0, 0, "REG", "Register", "PHY register address, 0 to 31.");
    Reg#(Bit#(5))  rg_phy_addr    <- csr_reg_rw('h00, 0, 8, "PHY", "PHY address", "MDIO PHY address, 0 to 31.");

    csr_reg_def('h04, "MDIO_WRITE_DATA", "Data for the next write");
    Reg#(Bit#(16)) rg_write_data  <- csr_reg_rw('h04, 0, 0, "DATA", "Write data", "Latched when COMMAND is accepted.");

    csr_reg_def('h08, "MDIO_COMMAND", "Full-word write READ=1 or WRITE=2; busy and invalid commands return SLVERR");

    csr_reg_def('h0c, "MDIO_STATUS", "Busy and sticky completion/error flags");
    Reg#(Bool)     rg_busy        <- csr_reg_ro('h0c, False, 0, "BUSY", "Busy", "A frame or its completion is outstanding.");
    csr_reg_w1c('h0c, False, 1, w_done   ? tagged Valid True : tagged Invalid, "DONE",   "Done",   "Read or write completed; write one to clear.");
    csr_reg_w1c('h0c, False, 2, w_no_ack ? tagged Valid True : tagged Invalid, "NO_ACK", "No ACK", "PHY did not drive turnaround low on a read; write one to clear.");

    csr_reg_def('h10, "MDIO_READ_DATA", "Most recent read result");
    Reg#(Bit#(16)) rg_read_data   <- csr_reg_ro('h10, 0, 0, "DATA", "Read data", "Valid after a read completes with NO_ACK clear. Writes retain the last read result.");

    csr_reg_def('h14, "MDIO_DIVIDER", "Logic clock cycles per MDC half-period");
    Reg#(Bit#(16)) rg_divider     <- csr_reg_rw('h14, 64, 0, "CYCLES", "Half-period", "Values below four use four; latched when COMMAND is accepted.");

    csr_reg_def('h18, "MDIO_PHY_RESET", "Manual active-low PHY reset");
    Reg#(Bool)     rg_phy_reset_n <- csr_reg_rw('h18, False, 0, "RELEASE", "Release reset", "Zero holds the PHY in reset; software supplies reset and settling delays.");

    // Reject malformed and busy commands before invoking the request method.
    function Bool cmd_valid(Bit#(32) data, Bit#(4) strb);
        return strb == 'hf && (data == 1 || data == 2) && i_mdio.ready;
    endfunction

    // Accept the command and snapshot its configuration atomically with
    // the CSR response. The dispatch predicate validates data and strobes.
    function ActionValue#(BlueCSRResponse_t) exec_cmd(Bit#(32) data, Bit#(4) strb);
        actionvalue
            i_mdio.request.put(MdioRequest {
                read:     data == 1,
                phy_addr: rg_phy_addr,
                reg_addr: rg_reg_addr,
                data:     rg_write_data,
                divider:  rg_divider
            });
            return CSR_OKAY;
        endactionvalue
    endfunction

    csr_reg_act_wo('h08, Bit#(2)'(0), 0, cmd_valid, CSR_SLVERR, exec_cmd, "OP", "Command", "Full-word writes only (strobes 0xF). Write exactly 1 for READ or 2 for WRITE.");

    rule r_busy;
        rg_busy <= i_mdio.busy;
    endrule

    rule r_complete;
        let rsp <- i_mdio.response.get;
        if(rsp.read) rg_read_data <= rsp.data;
        w_done   <= True;
        w_no_ack <= rsp.no_ack;
    endrule

    interface pins = i_mdio.pins;
    method phy_reset_n = rg_phy_reset_n;
endmodule

module [BlueCSRCtx_t#(32, 32)] mdio_standalone_csrs(MdioControl_ifc);
    csr_regmap_def("MDIO", "Clause 22 MDIO master");
    let i_control <- mdio_csrs;
    return i_control;
endmodule

interface MdioCsr_ifc;
    interface BlueCSR_ifc#(32, 32, 0) csr;
    interface MdioPins_ifc            pins;
    method Bool                      phy_reset_n;
endinterface

module [Module] mkMdioCsr(MdioCsr_ifc);
    BlueCSRAccess_ifc#(32, 32, 0, MdioControl_ifc) i_csrs <- create_blue_csr(mdio_standalone_csrs, False);
    interface csr  = i_csrs.external;
    interface pins = i_csrs.internal.pins;
    method phy_reset_n = i_csrs.internal.phy_reset_n;
endmodule

interface MdioAxiLite_ifc;
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_wr;
    interface MdioPins_ifc                   pins;
    method Bool                             phy_reset_n;
endinterface

module [Module] mkMdioAxiLite(MdioAxiLite_ifc);
    let i_mdio <- mkMdioCsr;
    let i_axi  <- mkBlueCSRAXI4LiteAdapter(i_mdio.csr, 1, 1);
    interface s_rd = i_axi.s_rd;
    interface s_wr = i_axi.s_wr;
    interface pins = i_mdio.pins;
    method phy_reset_n = i_mdio.phy_reset_n;
endmodule

endpackage
