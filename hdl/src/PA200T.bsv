package PA200T;

import Vector :: *;
import Clocks :: *;
import Connectable :: *;
import DefaultValue :: *;

import BlueJ :: *;
import BlueAXI :: *;
import BlueXLNX :: *;
import Axi4Lite :: *;

import PA200T_JTAG :: *;
import PA200T_UART :: *;
import PA200T_ETH  :: *;
import PA200T_BUS  :: *;
import PA200T_PLL  :: *;

// Build without the UDP subsystem with `make ... NO_UDP=1`, the RGMII outputs are then tied low and the ETH/UDP_TRAFFIC bus regions answer DECERR.
`ifdef PA200T_NO_UDP
Bool pa200t_use_udp = False;
`else
Bool pa200t_use_udp = True;
`endif

// Fixed IDELAYE2 taps on RGMII RXD/RX_CTL (about 78 ps each). 11 centers the datasheet window, the post-route sweep gave setup/hold slack +0.50/+0.29 ns at 10 taps and +0.31/+0.42 ns at 12 taps.
Integer pa200t_rx_idelay_taps = 11;

typedef Bit#(1) IO;
typedef Vector#(24, Inout#(IO)) GPIOPins;

(* always_enabled *)
interface PA200T_ifc;

    //JTAG
    (* prefix="" *)                 method      Action      tms((*port="TMS"*) Bit#(1) t);
    (* prefix="" *)                 method      Action      tdi((*port="TDI"*) Bit#(1) t);
    (* prefix="", result="TDO" *)   method      Bit#(1)     tdo();

    //LEDs
    (* result = "LED" *)            method      Bit#(2)     leds;

    //UART
    (* prefix="uart" *)             method      Action      rx((*port="rx"*) Bit#(1) value);
    (* result="uart_tx" *)          method      Bit#(1)     tx;

    //MDIO
    (* result="mdio_phy_rstn" *)    method      Bit#(1)     phy_rstn;
    (* result="mdio_mdc" *)         method      Bit#(1)     mdc;
    (* prefix="mdio_mdio" *)        interface   Inout#(IO)  mdio;

    //RGMII to the RTL8211F
    (* prefix="rgmii" *)            interface   PA200T_RGMII_ifc rgmii;

    (* prefix="GPIO" *)             interface   GPIOPins    gpio;

endinterface

(* no_default_clock *)
module [Module] mkPA200T_Top#(Clock tck, Clock clk_p, Clock clk_n, Clock rgmii_rxc)(PA200T_ifc);
    let inst <- wrap_diff_clk(mkPA200T_Clocks(tck, rgmii_rxc, False, pa200t_use_udp), clk_p, clk_n);
    return inst;
endmodule

// Takes the 200 MHz board clock. The design runs on the PLL's 125 MHz, which is also the RGMII GTX clock, 200 MHz only feeds the IDELAYCTRL.
module [Module] mkPA200T_Clocks#(Clock tck, Clock rgmii_rxc, Bool use_bscane2, Bool use_udp)(PA200T_ifc);
    let clk_200 <- exposeCurrentClock;
    let i_pll   <- mkPA200T_PLL(clk_200);
    let inst    <- mkPA200T(tck, rgmii_rxc, use_bscane2, use_udp, clk_200, i_pll.rst_200, i_pll.clk_125_90, clocked_by i_pll.clk_125, reset_by i_pll.rst_125);
    return inst;
endmodule

module [Module] mkPA200T#(
    Clock tck,
    Clock rgmii_rxc,
    Bool  use_bscane2,
    Bool  use_udp,
    Clock clk_200,
    Reset rst_200,
    Clock clk_125_90
)(PA200T_ifc);

    let sys_clk     <- exposeCurrentClock;
    let sys_rstn    <- exposeCurrentReset;

    let trstn       <- mkAsyncResetFromCR(2, tck);

    IOBUFs_ifc#(24) i_gpio_pads <- mkIOBUFs(defaultValue);
    PA200T_UART_ifc i_uart      <- mkPA200T_UART;
    PA200T_MDIO_ifc i_mdio      <- mkPA200T_MDIO;
    
    //optional JTAG via pins
    PA200T_JTAG_ifc i_jtag                      = ?;
    JTAGSystem_ifc#(PA200T_JTAG_ifc) i_jtag_sys = ?;

    if(use_bscane2) begin
        i_jtag      <- mkPA200T_JTAG_BSCANE2();
    end else begin
        i_jtag_sys  <- mkPA200T_JTAG_NATIVE(sys_clk, sys_rstn, clocked_by tck, reset_by trstn);
        i_jtag      = i_jtag_sys.device_ifc;
    end

    //optional UDP/IP endpoint with traffic generator
    PA200T_UDP_ifc       i_udp     = ?;
    Axi4LiteSlaveFab_ifc#(32, 32) i_eth     = ?;
    Axi4LiteSlaveFab_ifc#(32, 32) i_traffic = ?;

    if(use_udp) begin
        i_udp       <- mkPA200T_UDP(clk_125_90, rgmii_rxc, clk_200, rst_200, pa200t_rx_idelay_taps);
        i_eth       = i_udp.eth;
        i_traffic   = i_udp.traffic;
    end else begin
        i_eth       <- mkPA200T_ErrorSlave;
        i_traffic   <- mkPA200T_ErrorSlave;
    end

    //JTAG-to-AXI master -> address-decoded peripheral bus
    Axi4LiteSlaveFab_ifc#(32, 32) i_bus <- mkPA200T_Bus(
        axi4_lite_slave_fab(i_uart.s_rd, i_uart.s_wr),
        axi4_lite_slave_fab(i_mdio.s_rd, i_mdio.s_wr),
        i_eth,
        i_traffic
    );

    mkConnection(axi4_lite_master_fab(i_jtag.m_axil_rd, i_jtag.m_axil_wr), i_bus);

    //the pads let the board pins of the system clock leave the top, the PLL clock itself is not a top-level clock
    ReadOnly#(Bit#(2)) p_leds     <- mkOBUFs(defaultValue, i_jtag.leds);
    ReadOnly#(Bit#(1)) p_uart_tx  <- mkOBUF(defaultValue, i_uart.tx);
    ReadOnly#(Bit#(1)) p_phy_rstn <- mkOBUF(defaultValue, pack(i_mdio.phy_rstn));
    ReadOnly#(Bit#(1)) p_mdc      <- mkOBUF(defaultValue, i_mdio.mdc);
    IBUF_ifc           p_uart_rx  <- mkIBUF(defaultValue, clk_200);

    //asynchronous at the pad, the UART synchronizes it
    rule r_uart_rx;
        i_uart.rx(p_uart_rx.i);
    endrule

    rule r_gpio_o;
        i_gpio_pads.o(0);
        i_gpio_pads.oe(0);
    endrule

    rule r_gpio_i;
        //not used
        //let gpio = i_gpio_pads.i;
    endrule


    method tms(b)   = !use_bscane2 ? i_jtag_sys.tms(b)  : noAction;
    method tdi(b)   = !use_bscane2 ? i_jtag_sys.tdi(b)  : noAction;
    method tdo      = !use_bscane2 ? i_jtag_sys.tdo     : defaultValue;
    method leds     = p_leds;
    method rx       = p_uart_rx.pad;
    method tx       = p_uart_tx;
    method phy_rstn = p_phy_rstn;
    method mdc      = p_mdc;
    
    interface mdio = i_mdio.mdio;
    interface gpio = i_gpio_pads.io;

    interface PA200T_RGMII_ifc rgmii;
        method txc      = use_udp ? i_udp.rgmii.txc     : 0;
        method txd      = use_udp ? i_udp.rgmii.txd     : 0;
        method tx_ctl   = use_udp ? i_udp.rgmii.tx_ctl  : 0;
        method Action rx(Bit#(4) rxd, Bit#(1) rx_ctl);
            if(use_udp) i_udp.rgmii.rx(rxd, rx_ctl);
        endmethod
    endinterface

endmodule

endpackage
