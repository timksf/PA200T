package EthernetBVI;

import EthernetTypes :: *;
import AXI4_Stream   :: *;

interface RawStreamSink_ifc;
    method Bool   tready;
    method Action ptvalid(Bool value);
    method Action ptdata(Bit#(8) value);
    method Action ptlast(Bool value);
    method Action ptuser(Bit#(1) value);
endinterface

interface RawStreamSource_ifc;
    method Bool    tvalid;
    method Bit#(8) tdata;
    method Bool    tlast;
    method Bit#(1) tuser;
    method Action  ptready(Bool value);
endinterface

function EthernetStreamSink_ifc stream_sink(RawStreamSink_ifc raw);
    return interface EthernetStreamSink_ifc;
        method tready  = raw.tready;
        method ptvalid = raw.ptvalid;
        method ptdata  = raw.ptdata;
        method ptlast  = raw.ptlast;
        method ptuser  = raw.ptuser;
        method Action ptkeep(Bit#(1) value); endmethod
        method Action ptDest(Bit#(4) value); endmethod
        method Action ptid(Bit#(8) value); endmethod
    endinterface;
endfunction

function EthernetStreamSource_ifc stream_source(RawStreamSource_ifc raw);
    return interface EthernetStreamSource_ifc;
        method         tvalid  = raw.tvalid;
        method         tdata   = raw.tdata;
        method         tlast   = raw.tlast;
        method         tuser   = raw.tuser;
        method         ptready = raw.ptready;
        method Bit#(1) tkeep   = 1;
        method Bit#(4) tDest   = 0;
        method Bit#(8) tid     = 0;
    endinterface;
endfunction

endpackage
