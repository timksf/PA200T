package RgmiiMac;

import Clocks        :: *;
import GetPut        :: *;
import DefaultValue  :: *;
import EthernetTypes :: *;
import EthernetBVI   :: *;

typedef struct {
    String  target;
    String  ioddr_style;
    String  clock_input_style;
    String  use_clk90;
    Integer tx_fifo_depth;
    Integer rx_fifo_depth;
} RgmiiMacParameters;

instance DefaultValue#(RgmiiMacParameters);
    function defaultValue = RgmiiMacParameters {
        target:            "XILINX",
        ioddr_style:       "IODDR",
        clock_input_style: "BUFR",
        use_clk90:         "TRUE",
        tx_fifo_depth:     4096,
        rx_fifo_depth:     4096
    };
endinstance

typedef struct {
    Bool    tx_error_underflow;
    Bool    tx_fifo_overflow;
    Bool    tx_fifo_bad_frame;
    Bool    tx_fifo_good_frame;
    Bool    rx_error_bad_frame;
    Bool    rx_error_bad_fcs;
    Bool    rx_fifo_overflow;
    Bool    rx_fifo_bad_frame;
    Bool    rx_fifo_good_frame;
    Bit#(2) speed;
} RgmiiMacStatus deriving(Bits, Eq, FShow);

interface RgmiiPins_ifc;
    interface Clock tx_clk;
    (* always_ready, always_enabled *)
    method Action  rx_data(Bit#(4) rxd, Bit#(1) rx_ctl);
    method Bit#(4) tx_data;
    method Bit#(1) tx_ctl;
endinterface

interface RawRgmiiMac_ifc;
    interface RawStreamSink_ifc   tx;
    interface RawStreamSource_ifc rx;
    method Bool    tx_error_underflow;
    method Bool    tx_fifo_overflow;
    method Bool    tx_fifo_bad_frame;
    method Bool    tx_fifo_good_frame;
    method Bool    rx_error_bad_frame;
    method Bool    rx_error_bad_fcs;
    method Bool    rx_fifo_overflow;
    method Bool    rx_fifo_bad_frame;
    method Bool    rx_fifo_good_frame;
    method Bit#(2) speed;
    interface Clock               tx_clk;
    method Action  rx_data(Bit#(4) rxd, Bit#(1) rx_ctl);
    method Bit#(4) tx_data;
    method Bit#(1) tx_ctl;
    method Action  configure(Bit#(8) ifg, Bool tx_enable, Bool rx_enable);
endinterface

interface RgmiiMac_ifc;
    interface EthernetStreamSink_ifc   tx;
    interface EthernetStreamSource_ifc rx;
    interface RgmiiPins_ifc            pins;
    (* always_ready, always_enabled *)
    method Action         configure(Bit#(8) ifg, Bool tx_enable, Bool rx_enable);
    method RgmiiMacStatus status;
endinterface

import "BVI" eth_mac_1g_rgmii_fifo =
module vMkRgmiiMac#(
    Reset              rst_high,
    RgmiiMacParameters params,
    Clock              gtx_clk,
    Clock              gtx_clk90,
    Reset              gtx_rst_high,
    Clock              rgmii_rx_clk
)(RawRgmiiMac_ifc);

    default_clock clk(logic_clk);
    // Keep method resets in the enclosing BSV domain; the RTL reset is active high.
    default_reset rst();
    input_reset rtl_reset(logic_rst)   clocked_by(clk)       = rst_high;
    input_clock gtx_clock(gtx_clk)                           = gtx_clk;
    input_clock gtx_clock90(gtx_clk90)                       = gtx_clk90;
    input_reset gtx_reset(gtx_rst)     clocked_by(gtx_clock) = gtx_rst_high;
    input_clock rx_clock(rgmii_rx_clk)                       = rgmii_rx_clk;

    parameter TARGET            = params.target;
    parameter IODDR_STYLE       = params.ioddr_style;
    parameter CLOCK_INPUT_STYLE = params.clock_input_style;
    parameter USE_CLK90         = params.use_clk90;
    parameter TX_FIFO_DEPTH     = params.tx_fifo_depth;
    parameter RX_FIFO_DEPTH     = params.rx_fifo_depth;
    parameter AXIS_DATA_WIDTH   = 8;
    parameter AXIS_KEEP_ENABLE  = 0;
    port tx_axis_tkeep = Bit#(1)'(1);
    interface RawStreamSink_ifc tx;
        method ptvalid(tx_axis_tvalid) enable((*inhigh*) EN_tx_valid);
        method ptdata (tx_axis_tdata)  enable((*inhigh*) EN_tx_data);
        method ptlast (tx_axis_tlast)  enable((*inhigh*) EN_tx_last);
        method ptuser (tx_axis_tuser)  enable((*inhigh*) EN_tx_user);
        method tx_axis_tready tready;
    endinterface
    interface RawStreamSource_ifc rx;
        method rx_axis_tvalid tvalid;
        method rx_axis_tdata  tdata;
        method rx_axis_tlast  tlast;
        method rx_axis_tuser  tuser;
        method ptready(rx_axis_tready) enable((*inhigh*) EN_rx_ready);
    endinterface
    method tx_error_underflow tx_error_underflow;
    method tx_fifo_overflow   tx_fifo_overflow;
    method tx_fifo_bad_frame  tx_fifo_bad_frame;
    method tx_fifo_good_frame tx_fifo_good_frame;
    method rx_error_bad_frame rx_error_bad_frame;
    method rx_error_bad_fcs   rx_error_bad_fcs;
    method rx_fifo_overflow   rx_fifo_overflow;
    method rx_fifo_bad_frame  rx_fifo_bad_frame;
    method rx_fifo_good_frame rx_fifo_good_frame;
    method speed              speed;
    output_clock tx_clk(rgmii_tx_clk);
    method rx_data(rgmii_rxd, rgmii_rx_ctl) enable((*inhigh*) EN_RX_DATA) clocked_by(rx_clock) reset_by(no_reset);
    method rgmii_txd          tx_data clocked_by(no_clock) reset_by(no_reset);
    method rgmii_tx_ctl       tx_ctl clocked_by(no_clock) reset_by(no_reset);
    method configure(cfg_ifg, cfg_tx_enable, cfg_rx_enable) enable((*inhigh*) EN_CONFIG);

    schedule (
        tx.tready, rx.tvalid, rx.tdata, rx.tlast, rx.tuser, tx_error_underflow, tx_fifo_overflow,
        tx_fifo_bad_frame, tx_fifo_good_frame, rx_error_bad_frame, rx_error_bad_fcs, rx_fifo_overflow,
        rx_fifo_bad_frame, rx_fifo_good_frame, speed, tx_data, tx_ctl
    ) CF (
        tx.tready, rx.tvalid, rx.tdata, rx.tlast, rx.tuser, tx_error_underflow, tx_fifo_overflow,
        tx_fifo_bad_frame, tx_fifo_good_frame, rx_error_bad_frame, rx_error_bad_fcs, rx_fifo_overflow,
        rx_fifo_bad_frame, rx_fifo_good_frame, speed, tx_data, tx_ctl
    );
    schedule (
        tx.ptvalid, tx.ptdata, tx.ptlast, tx.ptuser, rx.ptready, rx_data, configure
    ) CF (
        tx.tready, rx.tvalid, rx.tdata, rx.tlast, rx.tuser, tx_error_underflow, tx_fifo_overflow,
        tx_fifo_bad_frame, tx_fifo_good_frame, rx_error_bad_frame, rx_error_bad_fcs, rx_fifo_overflow,
        rx_fifo_bad_frame, rx_fifo_good_frame, speed, tx_data, tx_ctl
    );
    schedule tx.ptvalid C tx.ptvalid;
    schedule tx.ptvalid CF (
        tx.ptdata, tx.ptlast, tx.ptuser, rx.ptready, rx_data, configure
    );
    schedule tx.ptdata C tx.ptdata;
    schedule tx.ptdata CF (
        tx.ptlast, tx.ptuser, rx.ptready, rx_data, configure
    );
    schedule tx.ptlast C tx.ptlast;
    schedule tx.ptlast CF (
        tx.ptuser, rx.ptready, rx_data, configure
    );
    schedule tx.ptuser C tx.ptuser;
    schedule tx.ptuser CF (
        rx.ptready, rx_data, configure
    );
    schedule rx.ptready C rx.ptready;
    schedule rx.ptready CF (
        rx_data, configure
    );
    schedule rx_data C rx_data;
    schedule rx_data CF (
        configure
    );
    schedule configure C configure;
endmodule

module mkRgmiiMac#(
    RgmiiMacParameters params,
    Clock              gtx_clk,
    Clock              gtx_clk90,
    Reset              gtx_rst_n,
    Clock              rgmii_rx_clk
)(RgmiiMac_ifc);
    let gtx_rst <- mkResetInverter(gtx_rst_n, clocked_by gtx_clk);
    let rst_n   <- exposeCurrentReset;
    let rst     <- mkResetInverter(rst_n);
    let i_raw   <- vMkRgmiiMac(rst, params, gtx_clk, gtx_clk90, gtx_rst, rgmii_rx_clk);

    interface tx = stream_sink(i_raw.tx);
    interface rx = stream_source(i_raw.rx);
    interface RgmiiPins_ifc pins;
        interface tx_clk = i_raw.tx_clk;
        method rx_data = i_raw.rx_data;
        method tx_data = i_raw.tx_data;
        method tx_ctl  = i_raw.tx_ctl;
    endinterface
    method                configure = i_raw.configure;
    method RgmiiMacStatus status    = RgmiiMacStatus {
        tx_error_underflow: i_raw.tx_error_underflow,
        tx_fifo_overflow:   i_raw.tx_fifo_overflow,
        tx_fifo_bad_frame:  i_raw.tx_fifo_bad_frame,
        tx_fifo_good_frame: i_raw.tx_fifo_good_frame,
        rx_error_bad_frame: i_raw.rx_error_bad_frame,
        rx_error_bad_fcs:   i_raw.rx_error_bad_fcs,
        rx_fifo_overflow:   i_raw.rx_fifo_overflow,
        rx_fifo_bad_frame:  i_raw.rx_fifo_bad_frame,
        rx_fifo_good_frame: i_raw.rx_fifo_good_frame,
        speed:              i_raw.speed
    };
endmodule

endpackage
