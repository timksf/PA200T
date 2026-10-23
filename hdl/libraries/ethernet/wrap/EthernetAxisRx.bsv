package EthernetAxisRx;

import Clocks        :: *;
import GetPut        :: *;
import EthernetTypes :: *;
import EthernetBVI   :: *;

interface RawEthernetAxisRx_ifc;
    interface RawStreamSink_ifc   axis;
    method Action   accept_header;
    method Bit#(48) header_dest_mac;
    method Bit#(48) header_src_mac;
    method Bit#(16) header_eth_type;
    interface RawStreamSource_ifc payload;
    method Bool     busy;
    method Bool     error_header_early_termination;
endinterface

interface EthernetAxisRx_ifc;
    interface EthernetStreamSink_ifc   axis;
    interface Get#(EthernetHeader)     header;
    interface EthernetStreamSource_ifc payload;
    method Bool busy;
    method Bool error_header_early_termination;
endinterface

import "BVI" eth_axis_rx =
module vMkEthernetAxisRx#(Reset rst_high)(RawEthernetAxisRx_ifc);

    default_clock clk(clk);
    // Keep method resets in the enclosing BSV domain; the RTL reset is active high.
    default_reset rst();
    input_reset rtl_reset(rst) clocked_by(clk) = rst_high;

    parameter DATA_WIDTH  = 8;
    parameter KEEP_ENABLE = 0;
    port s_axis_tkeep = Bit#(1)'(1);
    interface RawStreamSink_ifc axis;
        method ptvalid(s_axis_tvalid) enable((*inhigh*) EN_axis_valid);
        method ptdata (s_axis_tdata)  enable((*inhigh*) EN_axis_data);
        method ptlast (s_axis_tlast)  enable((*inhigh*) EN_axis_last);
        method ptuser (s_axis_tuser)  enable((*inhigh*) EN_axis_user);
        method s_axis_tready tready;
    endinterface
    method accept_header() enable(m_eth_hdr_ready) ready(m_eth_hdr_valid);
    method m_eth_dest_mac                 header_dest_mac;
    method m_eth_src_mac                  header_src_mac;
    method m_eth_type                     header_eth_type;
    interface RawStreamSource_ifc payload;
        method m_eth_payload_axis_tvalid tvalid;
        method m_eth_payload_axis_tdata  tdata;
        method m_eth_payload_axis_tlast  tlast;
        method m_eth_payload_axis_tuser  tuser;
        method ptready(m_eth_payload_axis_tready) enable((*inhigh*) EN_payload_ready);
    endinterface
    method busy                           busy;
    method error_header_early_termination error_header_early_termination;

    schedule (
        axis.tready, header_dest_mac, header_src_mac, header_eth_type, payload.tvalid, payload.tdata,
        payload.tlast, payload.tuser, busy, error_header_early_termination
    ) CF (
        axis.tready, header_dest_mac, header_src_mac, header_eth_type, payload.tvalid, payload.tdata,
        payload.tlast, payload.tuser, busy, error_header_early_termination
    );
    schedule (
        axis.ptvalid, axis.ptdata, axis.ptlast, axis.ptuser, payload.ptready, accept_header
    ) CF (
        axis.tready, header_dest_mac, header_src_mac, header_eth_type, payload.tvalid, payload.tdata,
        payload.tlast, payload.tuser, busy, error_header_early_termination
    );
    schedule axis.ptvalid C axis.ptvalid;
    schedule axis.ptvalid CF (
        axis.ptdata, axis.ptlast, axis.ptuser, payload.ptready, accept_header
    );
    schedule axis.ptdata C axis.ptdata;
    schedule axis.ptdata CF (
        axis.ptlast, axis.ptuser, payload.ptready, accept_header
    );
    schedule axis.ptlast C axis.ptlast;
    schedule axis.ptlast CF (
        axis.ptuser, payload.ptready, accept_header
    );
    schedule axis.ptuser C axis.ptuser;
    schedule axis.ptuser CF (
        payload.ptready, accept_header
    );
    schedule payload.ptready C payload.ptready;
    schedule payload.ptready CF (
        accept_header
    );
    schedule accept_header C accept_header;
endmodule

module mkEthernetAxisRx(EthernetAxisRx_ifc);
    let rst_n <- exposeCurrentReset;
    let rst   <- mkResetInverter(rst_n);
    let i_raw <- vMkEthernetAxisRx(rst);

    interface axis = stream_sink(i_raw.axis);
    interface Get header;
        method ActionValue#(EthernetHeader) get;
            i_raw.accept_header;
            return EthernetHeader {
                dest_mac: i_raw.header_dest_mac,
                src_mac:  i_raw.header_src_mac,
                eth_type: i_raw.header_eth_type
            };
        endmethod
    endinterface
    interface payload                     = stream_source(i_raw.payload);
    method busy                           = i_raw.busy;
    method error_header_early_termination = i_raw.error_header_early_termination;
endmodule

endpackage
