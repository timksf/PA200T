package PA200T;

import Vector :: *;
import Clocks :: *;
import DefaultValue :: *;

import BlueXLNX :: *;

import PA200T_JTAG :: *;

(* always_enabled *)
interface PA200T_ifc;

    (* result = "LED" *) method Bit#(2) leds;

    (* prefix = "GPIO" *)
    interface Vector#(24, Inout#(Bit#(1))) gpio; 

endinterface

(* no_default_clock *)
module [Module] mkPA200T_Top#(Clock clk_p, Clock clk_n)(PA200T_ifc);
    let inst <- wrap_diff_clk(mkPA200T, clk_p, clk_n);
    return inst;
endmodule

module mkPA200T(PA200T_ifc);

    let sys_clk     <- exposeCurrentClock;
    let sys_rstn    <- exposeCurrentReset;

    IOBUFs_ifc#(24)         i_gpio_pads <- mkIOBUFs(defaultValue);
    PA200T_JTAG_BSCANE2_ifc i_jtag      <- mkPA200T_JTAG_BSCANE2();

    rule r_gpio_o;
        i_gpio_pads.o(0);
        i_gpio_pads.oe(0);
    endrule

    rule r_gpio_i;
        //not used
        //let gpio = i_gpio_pads.i;
    endrule

    method leds = i_jtag.leds;
    
    interface gpio = i_gpio_pads.io;

endmodule

endpackage
