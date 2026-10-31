package PA200T_ETH;

import Clocks :: *;
import Connectable :: *;
import DefaultValue :: *;
import GetPut :: *;

import BlueAXI :: *;
import BlueXLNX :: *;
import Axi4Lite :: *;

import Ethernet :: *;

//MDIO only interface
(* always_ready, always_enabled *)
interface PA200T_MDIO_ifc;

    //pins
    method Bool phy_rstn;

    method Bit#(1) mdc;
    interface Inout#(Bit#(1)) mdio;

    //csr access
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_wr;

endinterface

module [Module] mkPA200T_MDIO(PA200T_MDIO_ifc);
    
    IOBUF_Config_t io_cfg = defaultValue;

    MdioAxiLite_ifc i_mdio  <- mkMdioAxiLite;
    IOBUF_ifc       i_io    <- mkIOBUF(io_cfg);

    mkConnection(i_io.i,                i_mdio.pins.mdio_i);
    mkConnection(i_mdio.pins.mdio_o,    i_io.o);
    
    rule rmdio_oe;
        i_io.oe(pack(i_mdio.pins.mdio_oe));
    endrule

    method phy_rstn = i_mdio.phy_reset_n;
    method mdc      = i_mdio.pins.mdc;

    interface mdio  = i_io.io;
    interface s_rd  = i_mdio.s_rd;
    interface s_wr  = i_mdio.s_wr;

endmodule

// RGMII pads of the RTL8211F. Its straps enable the RX clock delay and disable the TX clock delay, so the FPGA shifts TXC by 90 degrees and samples RX directly.
(* always_ready, always_enabled *)
interface PA200T_RGMII_ifc;
    method Bit#(1) txc;
    method Bit#(4) txd;
    method Bit#(1) tx_ctl;
    (* prefix="" *)
    method Action  rx((* port="rxd" *) Bit#(4) rxd, (* port="rx_ctl" *) Bit#(1) rx_ctl);
endinterface

interface PA200T_UDP_ifc;
    interface PA200T_RGMII_ifc              rgmii;
    interface Axi4LiteSlaveFab_ifc#(32, 32) eth;        //UDP/IP endpoint registers
    interface Axi4LiteSlaveFab_ifc#(32, 32) traffic;    //traffic generator and counters
endinterface

// UDP/IPv4/ARP endpoint with the throughput test block attached. Runs on the current clock, which must be the 125 MHz GTX clock for 1 Gb/s.
// PHY management stays with mkPA200T_MDIO, the endpoint's own MDIO registers are unused.
module [Module] mkPA200T_UDP#(
    Clock   clk_125_90,
    Clock   rgmii_rxc,
    Clock   clk_200,
    Reset   rst_200,
    Integer rx_idelay_taps
)(PA200T_UDP_ifc);

    let clk_125 <- exposeCurrentClock;
    let rst_125 <- exposeCurrentReset;

    //defaults: Artix-7 IDDR/ODDR, BUFIO/BUFR RX clocking, 90 degree TX clock
    RgmiiMacParameters mac_params = defaultValue;
    UdpParameters      udp_params = defaultValue;

    UdpRgmiiAxiLite_ifc   i_eth     <- mkUdpRgmiiAxiLite(udp_params, mac_params, clk_125, clk_125_90, rst_125, rgmii_rxc);
    UdpTrafficAxiLite_ifc i_traffic <- mkUdpTrafficAxiLite;

    //RX data and control pass an IDELAYE2 to match the BUFIO delay of RXC
    IDELAYE2s_Fixed_ifc#(5) i_rx_delay <- mkIDELAYE2s_Fixed(idelaye2_fixed(rx_idelay_taps), clocked_by rgmii_rxc, reset_by noReset);
    IDELAYCTRL_ifc          i_dly_ctrl <- mkIDELAYCTRL(clocked_by clk_200, reset_by rst_200);

    mkConnection(i_traffic.tx_header,  i_eth.tx_header);
    mkConnection(i_traffic.tx_payload, i_eth.tx_payload);
    mkConnection(i_eth.rx_header,      i_traffic.rx_header);
    mkConnection(i_eth.rx_payload,     i_traffic.rx_payload);

    //TXC is a DDR output of the MAC; as a plain bit it needs no clock port
    ReadOnly#(Bit#(1)) w_txc <- mkClockValue(i_eth.pins.tx_clk);

    rule r_mdio_unused;
        i_eth.mdio.mdio_i(1);
    endrule

    interface PA200T_RGMII_ifc rgmii;
        method txc      = w_txc;
        method txd      = i_eth.pins.tx_data;
        method tx_ctl   = i_eth.pins.tx_ctl;
        method Action rx(Bit#(4) rxd, Bit#(1) rx_ctl);
            i_rx_delay.i({rx_ctl, rxd});
            Bit#(5) d = i_rx_delay.o;
            i_eth.pins.rx_data(d[3:0], d[4]);
        endmethod
    endinterface

    interface eth     = axi4_lite_slave_fab(i_eth.s_rd, i_eth.s_wr);
    interface traffic = axi4_lite_slave_fab(i_traffic.s_rd, i_traffic.s_wr);

endmodule

endpackage
