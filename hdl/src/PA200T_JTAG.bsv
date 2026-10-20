package PA200T_JTAG;

import Clocks :: *;

import BlueJ :: *;
import BlueAXI :: *;
import JTAG2AXI :: *;

typedef struct {
    Bit#(w) blink_div;
    Bit#(n) blink_en;
} JTAG_LED_Ctrl#(numeric type n, numeric type w) deriving (Eq, Bits, FShow);

interface LEDControl_ifc#(numeric type n);
    method Bit#(n) pins;
endinterface

interface PA200T_JTAG_ifc;
    interface Bit#(2) leds;

    interface AXI4_Lite_Master_Rd_Fab#(32, 32) m_axil_rd;
    interface AXI4_Lite_Master_Wr_Fab#(32, 32) m_axil_wr;
endinterface

module mkLEDControl#(Reg#(JTAG_LED_Ctrl#(n, w)) rg_led_ctrl)(LEDControl_ifc#(n));

    Reg#(Bit#(w))  rg_div  <- mkReg(0);
    Reg#(Bit#(n))  rg_leds <- mkReg(0);

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

    method pins = rg_leds;

endmodule

//the bscan variant needs no pins as those are mapped implicitly by vivado
module [Module] mkPA200T_JTAG_BSCANE2(PA200T_JTAG_ifc);

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

    LEDControl_ifc#(2)                      i_leds          <- mkLEDControl(rg_led_ctrl);

    connect_bscane2_to_target(i_bscan3, jtag_led_ctrl.scan);
    connect_bscane2_to_target(i_bscan4, i_jtag2axil.scan);

    rule rupd_ctrl if(jtag_led_ctrl.wr_o());
        rg_led_ctrl <= jtag_led_ctrl.reg_o();
        $display("Updating control to: ", fshow(jtag_led_ctrl.reg_o()));
    endrule

    method leds = i_leds.pins;

    interface m_axil_rd = i_jtag2axil.m_axil_rd;
    interface m_axil_wr = i_jtag2axil.m_axil_wr;

endmodule

//custom tap variant
module [JTAGSystem#(2, 3)] pa200t_jtag_system#(Clock sys_clk, Reset sys_rst)(PA200T_JTAG_ifc);
    //the jtag system itself runs in the TCK domain, everything that leaves this domain has to use CDC

    jtag_meta_config(0, 'b00000010111, 'h04);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(0);
    jtag_rst_to_idcode();

    //jtag data registers
    JTAG2AXIL_ifc#(32, 32)      i_jtag2axil <- mkJTAG2AXI(sys_clk, sys_rst);
    Reg#(JTAG_LED_Ctrl#(2, 32)) rg_led_ctrl <- mkReg(unpack(0), clocked_by sys_clk, reset_by sys_rst);

    //led control
    LEDControl_ifc#(2)          i_leds      <- mkLEDControl(rg_led_ctrl, clocked_by sys_clk, reset_by sys_rst);

    //jtag system definition
    jtag_scan_endpoint(i_jtag2axil.scan,                'h03);
    jtag_sync_reg_io(unpack('hDEADBEEF), rg_led_ctrl,   'h04, sys_clk, sys_rst);


    method leds = i_leds.pins;

    interface m_axil_rd = i_jtag2axil.m_axil_rd;
    interface m_axil_wr = i_jtag2axil.m_axil_wr;

endmodule

module [Module] mkPA200T_JTAG_NATIVE#(Clock sys_clk, Reset sys_rst)(JTAGSystem_ifc#(PA200T_JTAG_ifc));
    let pa200t_jtag_sys <- build_jtag_system(pa200t_jtag_system(sys_clk, sys_rst));
    return pa200t_jtag_sys;
endmodule

endpackage