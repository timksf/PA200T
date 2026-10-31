package UdpTraffic;

import FIFOF                  :: *;
import Vector                 :: *;
import GetPut                 :: *;
import AXI4_Stream            :: *;
import AXI4_Lite_Slave        :: *;
import BlueCSRCore            :: *;
import BlueCSRAXI4LiteAdapter :: *;
import EthernetTypes          :: *;
import UdpRgmiiCsr            :: *;

// UDP packet generator and receive counters for throughput tests. Connect the
// ports to an mkUdpRgmiiCsr / mkUdpRgmiiAxiLite endpoint; addresses and ports of
// generated packets come from that endpoint's registers.
//
// Generated payload: 32-bit big-endian sequence number (0, 1, ...) followed by
// the low byte of the payload index. Received packets are checked for the same
// sequence header.

interface UdpTrafficPorts_ifc;
    interface Get#(UdpTxRequest)       tx_header;
    interface EthernetStreamSource_ifc tx_payload;
    interface Put#(UdpRxHeader)        rx_header;
    interface EthernetStreamSink_ifc   rx_payload;
endinterface

typedef enum { RX_IDLE, RX_COUNT, RX_ECHO, RX_DROP } UdpTrafficRxState deriving(Bits, Eq, FShow);

module [BlueCSRCtx_t#(32, 32)] udp_traffic_csrs(UdpTrafficPorts_ifc);
    csr_regmap_def("UdpTraffic", "UDP packet generator and receive counters for throughput tests");

    FIFOF#(UdpTxRequest)  f_tx_header   <- mkFIFOF;
    AXI4_Stream_Wr#(8, 1) i_tx          <- mkAXI4_Stream_Wr(2);
    FIFOF#(UdpRxHeader)   f_rx_header   <- mkFIFOF;
    AXI4_Stream_Rd#(8, 1) i_rx          <- mkAXI4_Stream_Rd(2);

    Reg#(Bit#(32))        rg_cycle      <- mkReg(0);

    csr_reg_def('h00, "VERSION", "Register map version");
    csr_reg_rc('h00, Bit#(32)'('h00010000), 0, "VERSION", "Version", "Version 1.0.");

    csr_reg_def('h04, "TX_START", "Any write starts the generator and clears the TX counters");
    csr_reg_wo('h04, Bit#(32)'(0), 0, "COMMAND", "Start", "Write any value.");
    Reg#(Bit#(1))         rg_tx_start   <- csr_reg_trigw('h04, True);

    csr_reg_def('h08, "TX_STOP", "Any write stops the generator after the current packet");
    csr_reg_wo('h08, Bit#(32)'(0), 0, "COMMAND", "Stop", "Write any value.");
    Reg#(Bit#(1))         rg_tx_stop    <- csr_reg_trigw('h08, True);

    csr_reg_def('h0c, "RX_CLEAR", "Any write clears the RX counters");
    csr_reg_wo('h0c, Bit#(32)'(0), 0, "COMMAND", "Clear", "Write any value.");
    Reg#(Bit#(1))         rg_rx_clear   <- csr_reg_trigw('h0c, True);

    csr_reg_def('h10, "TX_LENGTH", "Generated UDP payload length");
    Reg#(Bit#(16))        rg_length     <- csr_reg_rw('h10, 1472, 0, "BYTES", "Payload bytes", "1 to 1472 for a 1500-byte MTU; 0 sends nothing. Latched per packet.");

    csr_reg_def('h14, "TX_COUNT", "Packets per generator run");
    Reg#(Bit#(32))        rg_count      <- csr_reg_rw('h14, 0, 0, "PACKETS", "Packets", "0 runs until TX_STOP.");

    csr_reg_def('h18, "TX_GAP", "Idle cycles after each generated packet");
    Reg#(Bit#(16))        rg_gap        <- csr_reg_rw('h18, 0, 0, "CYCLES", "Gap", "Logic-clock cycles; limits the generated rate.");

    csr_reg_def('h1c, "CONTROL", "Receive handling");
    Reg#(Bool)            rg_echo       <- csr_reg_rw('h1c, False, 0, "ECHO", "Echo", "Send each accepted packet back to the endpoint's PEER_IP and ports. Keep the generator stopped.");

    csr_reg_def('h20, "RX_PORT", "Receive destination port filter");
    Reg#(Bit#(16))        rg_rx_port    <- csr_reg_rw('h20, 0, 0, "PORT", "Port", "Only packets to this UDP port are counted; 0 accepts every port.");

    csr_reg_def('h24, "STATUS", "Generator state");
    Reg#(Bool)            rg_tx_busy    <- csr_reg_ro('h24, False, 0, "TX_BUSY", "TX busy", "The generator is running.");

    csr_reg_def('h28, "TX_PACKETS", "Packets generated in this run");
    Reg#(Bit#(32))        rg_tx_packets <- csr_reg_ro('h28, 0, 0, "VALUE", "Packets", "Updated when a packet's last byte is accepted.");

    csr_reg_def('h2c, "TX_CYCLES", "Logic-clock cycles from TX_START to the last accepted byte");
    Reg#(Bit#(32))        rg_tx_cycles  <- csr_reg_ro('h2c, 0, 0, "VALUE", "Cycles", "Payload rate = TX_PACKETS * TX_LENGTH * 8 * f_clk / TX_CYCLES. Wraps after 2^32 cycles.");

    csr_reg_def('h30, "RX_PACKETS", "Accepted packets");
    Reg#(Bit#(32))        rg_rx_packets <- csr_reg_ro('h30, 0, 0, "VALUE", "Packets", "Packets passing the RX_PORT filter.");

    csr_reg_def('h34, "RX_BYTES", "Accepted payload bytes");
    Reg#(Bit#(32))        rg_rx_bytes   <- csr_reg_ro('h34, 0, 0, "VALUE", "Bytes", "Wraps after 2^32 bytes.");

    csr_reg_def('h38, "RX_CYCLES", "Logic-clock cycles from the first to the latest accepted packet end");
    Reg#(Bit#(32))        rg_rx_cycles  <- csr_reg_ro('h38, 0, 0, "VALUE", "Cycles", "Measured from the first payload byte after RX_CLEAR. Wraps after 2^32 cycles.");

    csr_reg_def('h3c, "RX_SEQ_ERRORS", "Sequence discontinuities");
    Reg#(Bit#(32))        rg_rx_seq_err <- csr_reg_ro('h3c, 0, 0, "VALUE", "Errors", "Packets whose sequence number is not the previous one plus one.");

    csr_reg_def('h40, "RX_BAD_FRAMES", "Packets ending with an error flag");
    Reg#(Bit#(32))        rg_rx_bad     <- csr_reg_ro('h40, 0, 0, "VALUE", "Bad frames", "Last payload byte had user[0] set.");

    csr_reg_def('h44, "RX_IGNORED", "Packets rejected by the RX_PORT filter");
    Reg#(Bit#(32))        rg_rx_ignored <- csr_reg_ro('h44, 0, 0, "VALUE", "Ignored", "Their payload is drained.");

    // generator state
    Reg#(Bit#(32))        rg_seq        <- mkReg(0);
    Reg#(Bit#(16))        rg_left       <- mkReg(0);
    Reg#(Bit#(16))        rg_index      <- mkReg(0);
    Reg#(Bit#(16))        rg_wait       <- mkReg(0);
    Reg#(Bit#(32))        rg_tx_t0      <- mkReg(0);

    // receive state
    Reg#(UdpTrafficRxState) rg_rx_state <- mkReg(RX_IDLE);
    Reg#(Bit#(16))        rg_rx_index   <- mkReg(0);
    Reg#(Bit#(24))        rg_rx_seq_hi  <- mkReg(0);
    Reg#(Bit#(32))        rg_rx_expect  <- mkReg(0);
    Reg#(Bool)            rg_rx_synced  <- mkReg(False);
    Reg#(Bool)            rg_rx_started <- mkReg(False);
    Reg#(Bit#(32))        rg_rx_t0      <- mkReg(0);

    Bool tx_more = rg_count == 0 || rg_seq < rg_count;

    rule r_cycle;
        rg_cycle <= rg_cycle + 1;
    endrule

    // A start or stop never cuts the packet in flight.
    rule r_tx_control(rg_tx_start == 1 || rg_tx_stop == 1);
        if(rg_tx_start == 1) begin
            rg_tx_busy    <= True;
            rg_seq        <= 0;
            rg_tx_packets <= 0;
            rg_tx_cycles  <= 0;
            rg_tx_t0      <= rg_cycle;
        end else begin
            rg_tx_busy    <= False;
        end
    endrule

    rule r_tx_header(rg_tx_busy && !rg_echo && rg_left == 0 && rg_wait == 0 && rg_length != 0 && tx_more);
        f_tx_header.enq(UdpTxRequest { payload_length: rg_length, checksum: 0 });
        rg_left  <= rg_length;
        rg_index <= 0;
    endrule

    (* descending_urgency = "r_tx_control, r_tx_data, r_tx_header" *)
    rule r_tx_data(rg_left != 0);
        Vector#(4, Bit#(8)) seq_bytes = reverse(unpack(rg_seq));
        Bit#(8) data = rg_index < 4 ? seq_bytes[rg_index[1:0]] : truncate(rg_index);
        Bool last = rg_left == 1;

        i_tx.pkg.put(AXI4_Stream_Pkg { data: data, user: 0, keep: 1, dest: 0, id: 0, last: last });
        rg_left  <= rg_left - 1;
        rg_index <= rg_index + 1;

        if(last) begin
            rg_seq        <= rg_seq + 1;
            rg_tx_packets <= rg_seq + 1;
            rg_tx_cycles  <= rg_cycle - rg_tx_t0;
            rg_wait       <= rg_gap;
            if(rg_count != 0 && rg_seq + 1 == rg_count) rg_tx_busy <= False;
        end
    endrule

    rule r_tx_gap(rg_left == 0 && rg_wait != 0);
        rg_wait <= rg_wait - 1;
    endrule

    function Bool rx_accept(UdpRxHeader hdr) = rg_rx_port == 0 || hdr.dest_port == rg_rx_port;

    rule r_rx_clear(rg_rx_clear == 1);
        rg_rx_packets <= 0;
        rg_rx_bytes   <= 0;
        rg_rx_cycles  <= 0;
        rg_rx_seq_err <= 0;
        rg_rx_bad     <= 0;
        rg_rx_ignored <= 0;
        rg_rx_synced  <= False;
        rg_rx_started <= False;
    endrule

    // Echo needs a payload; empty packets are only counted.
    rule r_rx_header_echo(rg_rx_state == RX_IDLE && rg_echo && rx_accept(f_rx_header.first) && f_rx_header.first.length > 8);
        let hdr = f_rx_header.first;
        f_rx_header.deq;
        f_tx_header.enq(UdpTxRequest { payload_length: hdr.length - 8, checksum: 0 });
        rg_rx_state <= RX_ECHO;
    endrule

    rule r_rx_header_count(rg_rx_state == RX_IDLE && !(rg_echo && rx_accept(f_rx_header.first) && f_rx_header.first.length > 8));
        let hdr = f_rx_header.first;
        f_rx_header.deq;
        if(!rx_accept(hdr)) begin
            rg_rx_ignored <= rg_rx_ignored + 1;
            rg_rx_state   <= hdr.length > 8 ? RX_DROP : RX_IDLE;
        end else if(hdr.length > 8) begin
            rg_rx_state   <= RX_COUNT;
        end else begin
            rg_rx_packets <= rg_rx_packets + 1;
        end
    endrule

    function Action rx_beat(AXI4_Stream_Pkg#(8, 1) beat);
        action
            Bool counted = rg_rx_state != RX_DROP;
            Bit#(32) rx_seq = {rg_rx_seq_hi, beat.data};

            rg_rx_index <= beat.last ? 0 : rg_rx_index + 1;
            if(rg_rx_index < 3) rg_rx_seq_hi <= {rg_rx_seq_hi[15:0], beat.data};
            if(beat.last) rg_rx_state <= RX_IDLE;

            if(counted) begin
                rg_rx_bytes <= rg_rx_bytes + 1;
                if(!rg_rx_started) begin
                    rg_rx_started <= True;
                    rg_rx_t0      <= rg_cycle;
                end
                if(rg_rx_index == 3) begin
                    if(rg_rx_synced && rx_seq != rg_rx_expect) rg_rx_seq_err <= rg_rx_seq_err + 1;
                    rg_rx_synced <= True;
                    rg_rx_expect <= rx_seq + 1;
                end
                if(beat.last) begin
                    rg_rx_packets <= rg_rx_packets + 1;
                    rg_rx_cycles  <= rg_rx_started ? rg_cycle - rg_rx_t0 : 0;
                    if(beat.user[0] == 1) rg_rx_bad <= rg_rx_bad + 1;
                end
            end
        endaction
    endfunction

    (* descending_urgency = "r_rx_payload_echo, r_tx_data" *)
    rule r_rx_payload_echo(rg_rx_state == RX_ECHO);
        let beat <- i_rx.pkg.get;
        i_tx.pkg.put(beat);
        rx_beat(beat);
    endrule

    (* descending_urgency = "r_rx_clear, r_rx_header_echo, r_rx_header_count, r_rx_payload_echo, r_rx_payload_count" *)
    rule r_rx_payload_count(rg_rx_state == RX_COUNT || rg_rx_state == RX_DROP);
        let beat <- i_rx.pkg.get;
        rx_beat(beat);
    endrule

    interface tx_header  = toGet(f_tx_header);
    interface tx_payload = i_tx.fab;
    interface rx_header  = toPut(f_rx_header);
    interface rx_payload = i_rx.fab;
endmodule

interface UdpTraffic_ifc;
    interface BlueCSR_ifc#(32, 32, 0)  csr;
    interface Get#(UdpTxRequest)       tx_header;
    interface EthernetStreamSource_ifc tx_payload;
    interface Put#(UdpRxHeader)        rx_header;
    interface EthernetStreamSink_ifc   rx_payload;
endinterface

module [Module] mkUdpTraffic(UdpTraffic_ifc);
    BlueCSRAccess_ifc#(32, 32, 0, UdpTrafficPorts_ifc) i_csrs <- create_blue_csr(udp_traffic_csrs, True);
    interface csr        = i_csrs.external;
    interface tx_header  = i_csrs.internal.tx_header;
    interface tx_payload = i_csrs.internal.tx_payload;
    interface rx_header  = i_csrs.internal.rx_header;
    interface rx_payload = i_csrs.internal.rx_payload;
endmodule

interface UdpTrafficAxiLite_ifc;
    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_wr;
    interface Get#(UdpTxRequest)              tx_header;
    interface EthernetStreamSource_ifc        tx_payload;
    interface Put#(UdpRxHeader)               rx_header;
    interface EthernetStreamSink_ifc          rx_payload;
endinterface

module [Module] mkUdpTrafficAxiLite(UdpTrafficAxiLite_ifc);
    let i_traffic <- mkUdpTraffic;
    let i_axi     <- mkBlueCSRAXI4LiteAdapter(i_traffic.csr, 1, 1);
    interface s_rd       = i_axi.s_rd;
    interface s_wr       = i_axi.s_wr;
    interface tx_header  = i_traffic.tx_header;
    interface tx_payload = i_traffic.tx_payload;
    interface rx_header  = i_traffic.rx_header;
    interface rx_payload = i_traffic.rx_payload;
endmodule

endpackage
