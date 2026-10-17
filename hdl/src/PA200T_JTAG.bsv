package PA200T_JTAG;

import Clocks :: *;

import BlueJ :: *;

interface PA200T_JTAG_BSCANE2_ifc;
    method Bit#(2) leds;
endinterface

typedef struct {
    Bit#(w) blink_div;
    Bit#(n) blink_en;
} JTAG_LED_Ctrl#(numeric type n, numeric type w) deriving (Eq, Bits, FShow);

//the bscan variant needs no pins as those are mapped implicitly by vivado
module mkPA200T_JTAG_BSCANE2(PA200T_JTAG_BSCANE2_ifc);

    let bscan_cfg = BSCANE2_Config {
        p_DISABLE_JTAG: False,
        p_JTAG_CHAIN: 3
    };

    let sys_clk <- exposeCurrentClock;
    let sys_rst <- exposeCurrentReset;
    
    let bscane2 <- mkBSCANE2(bscan_cfg);

    let tck     = bscane2.bscan_tck;
    let trst    <- mkAsyncResetFromCR(2, tck); //keep the jtag subsystem in reset for 2 tck cycles

    Reg#(JTAG_LED_Ctrl#(2, 32))             rg_led_ctrl     <- mkRegU;
    JTAG_Reg_ifc#(JTAG_LED_Ctrl#(2, 32))    jtag_led_ctrl   <- mkJTAG_Reg_Sync(unpack('hDEADBEEF), sys_clk, sys_rst, clocked_by tck, reset_by trst);

    Reg#(Bit#(32))  rg_div  <- mkReg(0);
    Reg#(Bit#(2))   rg_leds <- mkReg(0);

    connect_bscane2_to_target(bscane2, jtag_led_ctrl.scan);

    (* descending_urgency="rupd_ctrl, rdiv" *)
    rule rupd_ctrl if(jtag_led_ctrl.wr_o());
        rg_led_ctrl <= jtag_led_ctrl.reg_o();
        rg_div      <= 0;
        $display("Updating control to: ", fshow(jtag_led_ctrl.reg_o()));
    endrule

    rule rdiv;
        if(rg_div < zeroExtend(rg_led_ctrl.blink_div))
            rg_div <= rg_div + 1;
        else
            rg_div <= 0;
    endrule

    method leds = rg_leds;

endmodule

endpackage