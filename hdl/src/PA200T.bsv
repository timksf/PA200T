package PA200T;

import Vector :: *;
import Clocks :: *;
import Connectable :: *;
import DefaultValue :: *;

import BlueAXI :: *;
import BlueXLNX :: *;

import PA200T_JTAG :: *;
import PA200T_UART :: *;

(* always_enabled *)
interface PA200T_ifc;

    (* result = "LED" *)    
    method Bit#(2) leds;

    (* prefix="uart" *) method Action uart_rx((* port="rx" *) Bit#(1) value);
    method Bit#(1) uart_tx;

    (* prefix = "GPIO" *)
    interface Vector#(24, Inout#(Bit#(1))) gpio;

endinterface

(* no_default_clock *)
module [Module] mkPA200T_Top#(Clock clk_p, Clock clk_n)(PA200T_ifc);
    let inst <- wrap_diff_clk(mkPA200T, clk_p, clk_n);
    return inst;
endmodule

module [Module] mkPA200T(PA200T_ifc);

    let sys_clk     <- exposeCurrentClock;
    let sys_rstn    <- exposeCurrentReset;

    IOBUFs_ifc#(24)         i_gpio_pads <- mkIOBUFs(defaultValue);
    PA200T_JTAG_BSCANE2_ifc i_jtag      <- mkPA200T_JTAG_BSCANE2();
    PA200T_UART_ifc         i_uart      <- mkPA200T_UART;

    mkConnection(i_jtag.m_axil_rd, i_uart.s_rd);
    mkConnection(i_jtag.m_axil_wr, i_uart.s_wr);

    rule r_gpio_o;
        i_gpio_pads.o(0);
        i_gpio_pads.oe(0);
    endrule

    rule r_gpio_i;
        //not used
        //let gpio = i_gpio_pads.i;
    endrule

    method leds = i_jtag.leds;

    method uart_rx = i_uart.rx;
    method uart_tx = i_uart.tx;
    
    interface gpio = i_gpio_pads.io;

endmodule

endpackage
