package PA200T_PLL;

import Clocks :: *;
import DefaultValue :: *;

import BlueXLNX :: *;

interface PA200T_PLL_ifc;
    interface Clock clk_125;
    interface Reset rst_125;
endinterface

(* no_default_clock *)
module mkPA200T_PLL#(Clock clk_200)(PA200T_PLL_ifc);
    //200/8*5=125
    PLLE2_ADV_Config cfg_pll    = defaultValue;
    cfg_pll.p_CLKIN1_PERIOD     = 5.0;
    cfg_pll.p_CLKFBOUT_MULT     = 5;
    cfg_pll.p_CLKOUT0_DIVIDE    = 8;
    cfg_pll.p_COMPENSATION      = "INTERNAL";
    cfg_pll.p_IS_RST_INVERTED   = 1;

    let sys_rst         <- exposeCurrentReset;

    let i_feedback      <- mkClockWire(clocked_by clk_200);
    let i_pll           <- mkPLLE2_ADV(cfg_pll, clk_200, noClock, i_feedback.clk, clk_200, clocked_by clk_200);
    
    let feedback_value  <- mkClockValue(i_pll.clkfbout);
    let clk_out         <- mkBUFGClock(i_pll.clkout0);

    let i_lock_reset    <- mkResetWire(i_pll.locked);
    let reset_source    <- mkResetEither(sys_rst, i_lock_reset.rst, clocked_by clk_200);
    let rst_out         <- mkAsyncReset(2, reset_source, clk_out);

    rule r_pll_inputs;
        i_feedback.drive(feedback_value);
        i_pll.clkinsel(1);
        i_pll.pwrdwn(0);
        i_pll.daddr(0);
        i_pll.den(0);
        i_pll.d_i(0);
        i_pll.dwe(0);
    endrule

    interface clk_125 = clk_out;
    interface rst_125 = rst_out;
endmodule

endpackage
