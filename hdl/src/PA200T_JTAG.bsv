package PA200T_JTAG;

import Clocks :: *;

import BlueJ :: *;
import BlueAXI :: *;
import JTAG2AXI :: *;

interface PA200T_JTAG_BSCANE2_ifc;
    method Bit#(2) leds;

    interface AXI4_Lite_Master_Rd_Fab#(32, 32) m_axil_rd;
    interface AXI4_Lite_Master_Wr_Fab#(32, 32) m_axil_wr;

endinterface

typedef struct {
    Bit#(w) blink_div;
    Bit#(n) blink_en;
} JTAG_LED_Ctrl#(numeric type n, numeric type w) deriving (Eq, Bits, FShow);

//the bscan variant needs no pins as those are mapped implicitly by vivado
module [Module] mkPA200T_JTAG_BSCANE2(PA200T_JTAG_BSCANE2_ifc);

    let cfg_bscan_led = BSCANE2_Config { p_DISABLE_JTAG: False, p_JTAG_CHAIN: 3 };
    let cfg_bscan_axi = BSCANE2_Config { p_DISABLE_JTAG: False, p_JTAG_CHAIN: 4 };

    let sys_clk <- exposeCurrentClock;
    let sys_rst <- exposeCurrentReset;
    
    let i_bscan3 <- mkBSCANE2(cfg_bscan_led);
    let i_bscan4 <- mkBSCANE2(cfg_bscan_axi);

    let tck3     = i_bscan3.bscan_tck;
    let trst3    <- mkAsyncResetFromCR(2, tck3);

    let tck4     = i_bscan4.bscan_tck;
    let trst4    <- mkAsyncResetFromCR(2, tck4); //keep the jtag subsystem in reset for 2 tck cycles

    JTAG2AXIL_ifc#(32, 32)                  i_jtag2axil     <- mkJTAG2AXI(sys_clk, sys_rst, clocked_by tck4, reset_by trst4);

    Reg#(JTAG_LED_Ctrl#(2, 32))             rg_led_ctrl     <- mkRegU;
    JTAG_Reg_ifc#(JTAG_LED_Ctrl#(2, 32))    jtag_led_ctrl   <- mkJTAG_Reg_Sync(unpack('hDEADBEEF), sys_clk, sys_rst, clocked_by tck3, reset_by trst3);

    Reg#(Bit#(32))  rg_div  <- mkReg(0);
    Reg#(Bit#(2))   rg_leds <- mkReg(0);

    connect_bscane2_to_target(i_bscan3, jtag_led_ctrl.scan);
    connect_bscane2_to_target(i_bscan4, i_jtag2axil.scan);

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

    rule rtoggle if(rg_div == zeroExtend(rg_led_ctrl.blink_div));
        //turn off disabled leds and toggle enabled leds
        rg_leds <= (rg_leds ^ rg_led_ctrl.blink_en) & rg_led_ctrl.blink_en;
    endrule


    method leds = rg_leds;

    interface m_axil_rd = i_jtag2axil.m_axil_rd;
    interface m_axil_wr = i_jtag2axil.m_axil_wr;

endmodule

endpackage