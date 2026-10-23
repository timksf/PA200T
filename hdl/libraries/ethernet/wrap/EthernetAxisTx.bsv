package EthernetAxisTx;

import Clocks        :: *;
import GetPut        :: *;
import EthernetTypes :: *;
import EthernetBVI   :: *;

interface RawEthernetAxisTx_ifc;
    method Action send_header(Bit#(48) dest_mac, Bit#(48) src_mac, Bit#(16) eth_type);
    interface RawStreamSink_ifc   payload;
    interface RawStreamSource_ifc axis;
    method Bool   busy;
endinterface

interface EthernetAxisTx_ifc;
    interface Put#(EthernetHeader)     header;
    interface EthernetStreamSink_ifc   payload;
    interface EthernetStreamSource_ifc axis;
    method Bool busy;
endinterface

import "BVI" eth_axis_tx =
module vMkEthernetAxisTx#(Reset rst_high)(RawEthernetAxisTx_ifc);

    default_clock clk(clk);
    // Keep method resets in the enclosing BSV domain; the RTL reset is active high.
    default_reset rst();
    input_reset rtl_reset(rst) clocked_by(clk) = rst_high;

    parameter DATA_WIDTH  = 8;
    parameter KEEP_ENABLE = 0;
    port s_eth_payload_axis_tkeep = Bit#(1)'(1);
    method send_header(s_eth_dest_mac, s_eth_src_mac, s_eth_type) enable(s_eth_hdr_valid) ready(s_eth_hdr_ready);
    interface RawStreamSink_ifc payload;
        method ptvalid(s_eth_payload_axis_tvalid) enable((*inhigh*) EN_payload_valid);
        method ptdata (s_eth_payload_axis_tdata)  enable((*inhigh*) EN_payload_data);
        method ptlast (s_eth_payload_axis_tlast)  enable((*inhigh*) EN_payload_last);
        method ptuser (s_eth_payload_axis_tuser)  enable((*inhigh*) EN_payload_user);
        method s_eth_payload_axis_tready tready;
    endinterface
    interface RawStreamSource_ifc axis;
        method m_axis_tvalid tvalid;
        method m_axis_tdata  tdata;
        method m_axis_tlast  tlast;
        method m_axis_tuser  tuser;
        method ptready(m_axis_tready) enable((*inhigh*) EN_axis_ready);
    endinterface
    method busy busy;

    schedule (
        payload.tready, axis.tvalid, axis.tdata, axis.tlast, axis.tuser, busy
    ) CF (
        payload.tready, axis.tvalid, axis.tdata, axis.tlast, axis.tuser, busy
    );
    schedule (
        payload.ptvalid, payload.ptdata, payload.ptlast, payload.ptuser, axis.ptready, send_header
    ) CF (
        payload.tready, axis.tvalid, axis.tdata, axis.tlast, axis.tuser, busy
    );
    schedule payload.ptvalid C payload.ptvalid;
    schedule payload.ptvalid CF (
        payload.ptdata, payload.ptlast, payload.ptuser, axis.ptready, send_header
    );
    schedule payload.ptdata C payload.ptdata;
    schedule payload.ptdata CF (
        payload.ptlast, payload.ptuser, axis.ptready, send_header
    );
    schedule payload.ptlast C payload.ptlast;
    schedule payload.ptlast CF (
        payload.ptuser, axis.ptready, send_header
    );
    schedule payload.ptuser C payload.ptuser;
    schedule payload.ptuser CF (
        axis.ptready, send_header
    );
    schedule axis.ptready C axis.ptready;
    schedule axis.ptready CF (
        send_header
    );
    schedule send_header C send_header;
endmodule

module mkEthernetAxisTx(EthernetAxisTx_ifc);
    let rst_n <- exposeCurrentReset;
    let rst   <- mkResetInverter(rst_n);
    let i_raw <- vMkEthernetAxisTx(rst);

    interface Put header;
        method Action put(EthernetHeader hdr);
            i_raw.send_header(hdr.dest_mac, hdr.src_mac, hdr.eth_type);
        endmethod
    endinterface
    interface payload = stream_sink(i_raw.payload);
    interface axis    = stream_source(i_raw.axis);
    method busy = i_raw.busy;
endmodule

endpackage
