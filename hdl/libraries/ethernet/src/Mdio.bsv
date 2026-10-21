package Mdio;

import GetPut :: *;

typedef struct {
    Bool     read;
    Bit#(5)  phy_addr;
    Bit#(5)  reg_addr;
    Bit#(16) data;
    Bit#(16) divider;
} MdioRequest deriving(Bits, Eq, FShow);

typedef struct {
    Bool     read;
    Bit#(16) data;
    Bool     no_ack;
} MdioResponse deriving(Bits, Eq, FShow);

interface MdioPins_ifc;
    (* always_ready, always_enabled *)
    method Action  mdio_i(Bit#(1) value);
    method Bit#(1) mdio_o;
    method Bool    mdio_oe;
    method Bit#(1) mdc;
endinterface

interface MdioMaster_ifc;
    interface Put#(MdioRequest)  request;
    interface Get#(MdioResponse) response;
    interface MdioPins_ifc       pins;
    method Bool                 ready;
    method Bool                 busy;
endinterface

module mkMdioMaster(MdioMaster_ifc);
    Reg#(Bool)     rg_active       <- mkReg(False);
    Reg#(Bool)     rg_result_valid <- mkReg(False);
    Reg#(Bool)     rg_read         <- mkReg(False);
    Reg#(Bool)     rg_no_ack       <- mkReg(False);
    Reg#(Bool)     rg_mdc          <- mkReg(False);
    Reg#(Bit#(6))  rg_bit          <- mkReg(0);
    Reg#(Bit#(16)) rg_divider      <- mkReg(4);
    Reg#(Bit#(16)) rg_count        <- mkReg(0);
    Reg#(Bit#(64)) rg_shift        <- mkReg('1);
    Reg#(Bit#(16)) rg_data         <- mkReg(0);
    Reg#(Bit#(1))  rg_mdio_meta    <- mkReg(1);
    Reg#(Bit#(1))  rg_mdio_sync    <- mkReg(1);
    Wire#(Bit#(1)) w_mdio_i        <- mkDWire(1);
    PulseWire      w_complete      <- mkPulseWire;
    PulseWire      w_consume       <- mkPulseWire;

    rule r_result_valid;
        if(w_complete) rg_result_valid <= True;
        else if(w_consume) rg_result_valid <= False;
    endrule

    rule r_sample_input;
        rg_mdio_meta <= w_mdio_i;
        rg_mdio_sync <= rg_mdio_meta;
    endrule

    // One clock domain: clock enables generate MDC. Outputs change on falling
    // MDC edges; reads sample at the end of the high phase for PHY return delay.
    rule r_shift_frame if(rg_active);
        if(rg_count != 0) begin
            rg_count <= rg_count - 1;
        end
        else begin
            rg_count <= rg_divider - 1;
            rg_mdc   <= !rg_mdc;
            if(rg_mdc) begin
                // The PHY launches ACK on the first released rising edge,
                // followed by 16 data bits. Clock 63 drains the read idle bit.
                if(rg_read && rg_bit == 46) rg_no_ack <= unpack(rg_mdio_sync);
                if(rg_read && rg_bit >= 47 && rg_bit <= 62) rg_data   <= {rg_data[14:0], rg_mdio_sync};
                if(rg_bit == 63) begin
                    rg_active       <= False;
                    w_complete.send;
                end
                else begin
                    rg_bit   <= rg_bit + 1;
                    rg_shift <= {rg_shift[62:0], 1'b1};
                end
            end
        end
    endrule

    interface Put request;
        method Action put(MdioRequest req) if(!rg_active && !rg_result_valid);
            Bit#(16) divider = max(4, req.divider);
            Bit#(2)  opcode  = req.read ? 2'b10 : 2'b01;
            rg_active  <= True;
            rg_read    <= req.read;
            rg_no_ack  <= False;
            rg_mdc     <= False;
            rg_bit     <= 0;
            rg_divider <= divider;
            rg_count   <= divider - 1;
            rg_shift   <= {32'hffffffff, 2'b01, opcode, req.phy_addr, req.reg_addr, 2'b10, req.data};
            rg_data    <= 0;
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(MdioResponse) get if(rg_result_valid);
            w_consume.send;
            return MdioResponse {
                read:   rg_read,
                data:   rg_data,
                no_ack: rg_no_ack
            };
        endmethod
    endinterface

    interface MdioPins_ifc pins;
        method mdio_i  = w_mdio_i._write;
        method mdio_o  = rg_active ? rg_shift[63] : 1'b1;
        method mdio_oe = rg_active && !(rg_read && rg_bit >= 46);
        method mdc     = pack(rg_mdc);
    endinterface
    method ready = !rg_active && !rg_result_valid;
    method busy  = rg_active || rg_result_valid;
endmodule

endpackage
