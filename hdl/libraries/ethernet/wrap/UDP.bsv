package UDP;

import Clocks        :: *;
import GetPut        :: *;
import DefaultValue  :: *;
import EthernetTypes :: *;
import EthernetBVI   :: *;

typedef struct {
    Integer arp_cache_addr_width;
    Integer arp_request_retry_count;
    Integer arp_request_retry_interval;
    Integer arp_request_timeout;
    Integer checksum_payload_fifo_depth;
    Integer checksum_header_fifo_depth;
    Bool    checksum_gen_enable;
} UdpParameters;

instance DefaultValue#(UdpParameters);
    function defaultValue = UdpParameters {
        arp_cache_addr_width:        9,
        arp_request_retry_count:     4,
        arp_request_retry_interval:  250000000,
        arp_request_timeout:         3750000000,
        checksum_payload_fifo_depth: 2048,
        checksum_header_fifo_depth:  8,
        checksum_gen_enable:         True
    };
endinstance

typedef struct {
    Bool ip_rx_busy;
    Bool ip_tx_busy;
    Bool udp_rx_busy;
    Bool udp_tx_busy;
    Bool ip_rx_error_header_early_termination;
    Bool ip_rx_error_payload_early_termination;
    Bool ip_rx_error_invalid_header;
    Bool ip_rx_error_invalid_checksum;
    Bool ip_tx_error_payload_early_termination;
    Bool ip_tx_error_arp_failed;
    Bool udp_rx_error_header_early_termination;
    Bool udp_rx_error_payload_early_termination;
    Bool udp_tx_error_payload_early_termination;
} UdpStatus deriving(Bits, Eq, FShow);

interface RawUdpComplete_ifc;
    method Action   send_eth_rx(Bit#(48) dest_mac, Bit#(48) src_mac, Bit#(16) eth_type);
    interface RawStreamSink_ifc   eth_rx_payload;
    method Action   accept_eth_tx;
    method Bit#(48) eth_tx_dest_mac;
    method Bit#(48) eth_tx_src_mac;
    method Bit#(16) eth_tx_eth_type;
    interface RawStreamSource_ifc eth_tx_payload;
    method Action   send_ip_tx(Bit#(6) dscp, Bit#(2) ecn, Bit#(16) length, Bit#(8) ttl, Bit#(8) protocol, Bit#(32) source_ip, Bit#(32) dest_ip);
    interface RawStreamSink_ifc   ip_tx_payload;
    method Action   accept_ip_rx;
    method Bit#(48) ip_rx_eth_dest_mac;
    method Bit#(48) ip_rx_eth_src_mac;
    method Bit#(16) ip_rx_eth_type;
    method Bit#(4)  ip_rx_version;
    method Bit#(4)  ip_rx_ihl;
    method Bit#(6)  ip_rx_dscp;
    method Bit#(2)  ip_rx_ecn;
    method Bit#(16) ip_rx_length;
    method Bit#(16) ip_rx_identification;
    method Bit#(3)  ip_rx_flags;
    method Bit#(13) ip_rx_fragment_offset;
    method Bit#(8)  ip_rx_ttl;
    method Bit#(8)  ip_rx_protocol;
    method Bit#(16) ip_rx_header_checksum;
    method Bit#(32) ip_rx_source_ip;
    method Bit#(32) ip_rx_dest_ip;
    interface RawStreamSource_ifc ip_rx_payload;
    method Action   send_udp_tx(Bit#(6) ip_dscp, Bit#(2) ip_ecn, Bit#(8) ip_ttl, Bit#(32) ip_source_ip, Bit#(32) ip_dest_ip, Bit#(16) source_port, Bit#(16) dest_port, Bit#(16) length, Bit#(16) checksum);
    interface RawStreamSink_ifc   udp_tx_payload;
    method Action   accept_udp_rx;
    method Bit#(48) udp_rx_eth_dest_mac;
    method Bit#(48) udp_rx_eth_src_mac;
    method Bit#(16) udp_rx_eth_type;
    method Bit#(4)  udp_rx_ip_version;
    method Bit#(4)  udp_rx_ip_ihl;
    method Bit#(6)  udp_rx_ip_dscp;
    method Bit#(2)  udp_rx_ip_ecn;
    method Bit#(16) udp_rx_ip_length;
    method Bit#(16) udp_rx_ip_identification;
    method Bit#(3)  udp_rx_ip_flags;
    method Bit#(13) udp_rx_ip_fragment_offset;
    method Bit#(8)  udp_rx_ip_ttl;
    method Bit#(8)  udp_rx_ip_protocol;
    method Bit#(16) udp_rx_ip_header_checksum;
    method Bit#(32) udp_rx_ip_source_ip;
    method Bit#(32) udp_rx_ip_dest_ip;
    method Bit#(16) udp_rx_source_port;
    method Bit#(16) udp_rx_dest_port;
    method Bit#(16) udp_rx_length;
    method Bit#(16) udp_rx_checksum;
    interface RawStreamSource_ifc udp_rx_payload;
    method Bool     ip_rx_busy;
    method Bool     ip_tx_busy;
    method Bool     udp_rx_busy;
    method Bool     udp_tx_busy;
    method Bool     ip_rx_error_header_early_termination;
    method Bool     ip_rx_error_payload_early_termination;
    method Bool     ip_rx_error_invalid_header;
    method Bool     ip_rx_error_invalid_checksum;
    method Bool     ip_tx_error_payload_early_termination;
    method Bool     ip_tx_error_arp_failed;
    method Bool     udp_rx_error_header_early_termination;
    method Bool     udp_rx_error_payload_early_termination;
    method Bool     udp_tx_error_payload_early_termination;
    method Action   configure(Bit#(48) mac, Bit#(32) ip, Bit#(32) gateway, Bit#(32) mask, Bool clear_cache);
endinterface

interface UdpComplete_ifc;
    interface Put#(EthernetHeader)     eth_rx;
    interface EthernetStreamSink_ifc   eth_rx_payload;
    interface Get#(EthernetHeader)     eth_tx;
    interface EthernetStreamSource_ifc eth_tx_payload;
    interface Put#(IpTxHeader)         ip_tx;
    interface EthernetStreamSink_ifc   ip_tx_payload;
    interface Get#(IpRxHeader)         ip_rx;
    interface EthernetStreamSource_ifc ip_rx_payload;
    interface Put#(UdpTxHeader)        udp_tx;
    interface EthernetStreamSink_ifc   udp_tx_payload;
    interface Get#(UdpRxHeader)        udp_rx;
    interface EthernetStreamSource_ifc udp_rx_payload;
    (* always_ready, always_enabled *)
    method Action    configure(EthernetConfig cfg, Bool clear_cache);
    method UdpStatus status;
endinterface

import "BVI" udp_complete =
module vMkUdpComplete#(
    Reset         rst_high,
    UdpParameters params
)(RawUdpComplete_ifc);

    default_clock clk(clk);
    // Keep method resets in the enclosing BSV domain; the RTL reset is active high.
    default_reset rst();
    input_reset rtl_reset(rst) clocked_by(clk) = rst_high;

    parameter ARP_CACHE_ADDR_WIDTH            = params.arp_cache_addr_width;
    parameter ARP_REQUEST_RETRY_COUNT         = params.arp_request_retry_count;
    parameter ARP_REQUEST_RETRY_INTERVAL      = params.arp_request_retry_interval;
    parameter ARP_REQUEST_TIMEOUT             = params.arp_request_timeout;
    parameter UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH = params.checksum_payload_fifo_depth;
    parameter UDP_CHECKSUM_HEADER_FIFO_DEPTH  = params.checksum_header_fifo_depth;
    parameter UDP_CHECKSUM_GEN_ENABLE         = params.checksum_gen_enable ? 1 : 0;
    method send_eth_rx(s_eth_dest_mac, s_eth_src_mac, s_eth_type) enable(s_eth_hdr_valid) ready(s_eth_hdr_ready);
    interface RawStreamSink_ifc eth_rx_payload;
        method ptvalid(s_eth_payload_axis_tvalid) enable((*inhigh*) EN_eth_rx_payload_valid);
        method ptdata (s_eth_payload_axis_tdata)  enable((*inhigh*) EN_eth_rx_payload_data);
        method ptlast (s_eth_payload_axis_tlast)  enable((*inhigh*) EN_eth_rx_payload_last);
        method ptuser (s_eth_payload_axis_tuser)  enable((*inhigh*) EN_eth_rx_payload_user);
        method s_eth_payload_axis_tready tready;
    endinterface
    method accept_eth_tx() enable(m_eth_hdr_ready) ready(m_eth_hdr_valid);
    method m_eth_dest_mac                         eth_tx_dest_mac;
    method m_eth_src_mac                          eth_tx_src_mac;
    method m_eth_type                             eth_tx_eth_type;
    interface RawStreamSource_ifc eth_tx_payload;
        method m_eth_payload_axis_tvalid tvalid;
        method m_eth_payload_axis_tdata  tdata;
        method m_eth_payload_axis_tlast  tlast;
        method m_eth_payload_axis_tuser  tuser;
        method ptready(m_eth_payload_axis_tready) enable((*inhigh*) EN_eth_tx_payload_ready);
    endinterface
    method send_ip_tx(s_ip_dscp, s_ip_ecn, s_ip_length, s_ip_ttl, s_ip_protocol, s_ip_source_ip, s_ip_dest_ip) enable(s_ip_hdr_valid) ready(s_ip_hdr_ready);
    interface RawStreamSink_ifc ip_tx_payload;
        method ptvalid(s_ip_payload_axis_tvalid) enable((*inhigh*) EN_ip_tx_payload_valid);
        method ptdata (s_ip_payload_axis_tdata)  enable((*inhigh*) EN_ip_tx_payload_data);
        method ptlast (s_ip_payload_axis_tlast)  enable((*inhigh*) EN_ip_tx_payload_last);
        method ptuser (s_ip_payload_axis_tuser)  enable((*inhigh*) EN_ip_tx_payload_user);
        method s_ip_payload_axis_tready tready;
    endinterface
    method accept_ip_rx() enable(m_ip_hdr_ready) ready(m_ip_hdr_valid);
    method m_ip_eth_dest_mac                      ip_rx_eth_dest_mac;
    method m_ip_eth_src_mac                       ip_rx_eth_src_mac;
    method m_ip_eth_type                          ip_rx_eth_type;
    method m_ip_version                           ip_rx_version;
    method m_ip_ihl                               ip_rx_ihl;
    method m_ip_dscp                              ip_rx_dscp;
    method m_ip_ecn                               ip_rx_ecn;
    method m_ip_length                            ip_rx_length;
    method m_ip_identification                    ip_rx_identification;
    method m_ip_flags                             ip_rx_flags;
    method m_ip_fragment_offset                   ip_rx_fragment_offset;
    method m_ip_ttl                               ip_rx_ttl;
    method m_ip_protocol                          ip_rx_protocol;
    method m_ip_header_checksum                   ip_rx_header_checksum;
    method m_ip_source_ip                         ip_rx_source_ip;
    method m_ip_dest_ip                           ip_rx_dest_ip;
    interface RawStreamSource_ifc ip_rx_payload;
        method m_ip_payload_axis_tvalid tvalid;
        method m_ip_payload_axis_tdata  tdata;
        method m_ip_payload_axis_tlast  tlast;
        method m_ip_payload_axis_tuser  tuser;
        method ptready(m_ip_payload_axis_tready) enable((*inhigh*) EN_ip_rx_payload_ready);
    endinterface
    method send_udp_tx(s_udp_ip_dscp, s_udp_ip_ecn, s_udp_ip_ttl, s_udp_ip_source_ip, s_udp_ip_dest_ip, s_udp_source_port, s_udp_dest_port, s_udp_length, s_udp_checksum) enable(s_udp_hdr_valid) ready(s_udp_hdr_ready);
    interface RawStreamSink_ifc udp_tx_payload;
        method ptvalid(s_udp_payload_axis_tvalid) enable((*inhigh*) EN_udp_tx_payload_valid);
        method ptdata (s_udp_payload_axis_tdata)  enable((*inhigh*) EN_udp_tx_payload_data);
        method ptlast (s_udp_payload_axis_tlast)  enable((*inhigh*) EN_udp_tx_payload_last);
        method ptuser (s_udp_payload_axis_tuser)  enable((*inhigh*) EN_udp_tx_payload_user);
        method s_udp_payload_axis_tready tready;
    endinterface
    method accept_udp_rx() enable(m_udp_hdr_ready) ready(m_udp_hdr_valid);
    method m_udp_eth_dest_mac                     udp_rx_eth_dest_mac;
    method m_udp_eth_src_mac                      udp_rx_eth_src_mac;
    method m_udp_eth_type                         udp_rx_eth_type;
    method m_udp_ip_version                       udp_rx_ip_version;
    method m_udp_ip_ihl                           udp_rx_ip_ihl;
    method m_udp_ip_dscp                          udp_rx_ip_dscp;
    method m_udp_ip_ecn                           udp_rx_ip_ecn;
    method m_udp_ip_length                        udp_rx_ip_length;
    method m_udp_ip_identification                udp_rx_ip_identification;
    method m_udp_ip_flags                         udp_rx_ip_flags;
    method m_udp_ip_fragment_offset               udp_rx_ip_fragment_offset;
    method m_udp_ip_ttl                           udp_rx_ip_ttl;
    method m_udp_ip_protocol                      udp_rx_ip_protocol;
    method m_udp_ip_header_checksum               udp_rx_ip_header_checksum;
    method m_udp_ip_source_ip                     udp_rx_ip_source_ip;
    method m_udp_ip_dest_ip                       udp_rx_ip_dest_ip;
    method m_udp_source_port                      udp_rx_source_port;
    method m_udp_dest_port                        udp_rx_dest_port;
    method m_udp_length                           udp_rx_length;
    method m_udp_checksum                         udp_rx_checksum;
    interface RawStreamSource_ifc udp_rx_payload;
        method m_udp_payload_axis_tvalid tvalid;
        method m_udp_payload_axis_tdata  tdata;
        method m_udp_payload_axis_tlast  tlast;
        method m_udp_payload_axis_tuser  tuser;
        method ptready(m_udp_payload_axis_tready) enable((*inhigh*) EN_udp_rx_payload_ready);
    endinterface
    method ip_rx_busy                             ip_rx_busy;
    method ip_tx_busy                             ip_tx_busy;
    method udp_rx_busy                            udp_rx_busy;
    method udp_tx_busy                            udp_tx_busy;
    method ip_rx_error_header_early_termination   ip_rx_error_header_early_termination;
    method ip_rx_error_payload_early_termination  ip_rx_error_payload_early_termination;
    method ip_rx_error_invalid_header             ip_rx_error_invalid_header;
    method ip_rx_error_invalid_checksum           ip_rx_error_invalid_checksum;
    method ip_tx_error_payload_early_termination  ip_tx_error_payload_early_termination;
    method ip_tx_error_arp_failed                 ip_tx_error_arp_failed;
    method udp_rx_error_header_early_termination  udp_rx_error_header_early_termination;
    method udp_rx_error_payload_early_termination udp_rx_error_payload_early_termination;
    method udp_tx_error_payload_early_termination udp_tx_error_payload_early_termination;
    method configure(local_mac, local_ip, gateway_ip, subnet_mask, clear_arp_cache) enable((*inhigh*) EN_CONFIG);

    schedule (
        eth_rx_payload.tready, eth_tx_dest_mac, eth_tx_src_mac, eth_tx_eth_type, eth_tx_payload.tvalid,
        eth_tx_payload.tdata, eth_tx_payload.tlast, eth_tx_payload.tuser, ip_tx_payload.tready,
        ip_rx_eth_dest_mac, ip_rx_eth_src_mac, ip_rx_eth_type, ip_rx_version, ip_rx_ihl, ip_rx_dscp,
        ip_rx_ecn, ip_rx_length, ip_rx_identification, ip_rx_flags, ip_rx_fragment_offset, ip_rx_ttl,
        ip_rx_protocol, ip_rx_header_checksum, ip_rx_source_ip, ip_rx_dest_ip, ip_rx_payload.tvalid,
        ip_rx_payload.tdata, ip_rx_payload.tlast, ip_rx_payload.tuser, udp_tx_payload.tready,
        udp_rx_eth_dest_mac, udp_rx_eth_src_mac, udp_rx_eth_type, udp_rx_ip_version, udp_rx_ip_ihl,
        udp_rx_ip_dscp, udp_rx_ip_ecn, udp_rx_ip_length, udp_rx_ip_identification, udp_rx_ip_flags,
        udp_rx_ip_fragment_offset, udp_rx_ip_ttl, udp_rx_ip_protocol, udp_rx_ip_header_checksum,
        udp_rx_ip_source_ip, udp_rx_ip_dest_ip, udp_rx_source_port, udp_rx_dest_port, udp_rx_length,
        udp_rx_checksum, udp_rx_payload.tvalid, udp_rx_payload.tdata, udp_rx_payload.tlast,
        udp_rx_payload.tuser, ip_rx_busy, ip_tx_busy, udp_rx_busy, udp_tx_busy,
        ip_rx_error_header_early_termination, ip_rx_error_payload_early_termination,
        ip_rx_error_invalid_header, ip_rx_error_invalid_checksum, ip_tx_error_payload_early_termination,
        ip_tx_error_arp_failed, udp_rx_error_header_early_termination,
        udp_rx_error_payload_early_termination, udp_tx_error_payload_early_termination
    ) CF (
        eth_rx_payload.tready, eth_tx_dest_mac, eth_tx_src_mac, eth_tx_eth_type, eth_tx_payload.tvalid,
        eth_tx_payload.tdata, eth_tx_payload.tlast, eth_tx_payload.tuser, ip_tx_payload.tready,
        ip_rx_eth_dest_mac, ip_rx_eth_src_mac, ip_rx_eth_type, ip_rx_version, ip_rx_ihl, ip_rx_dscp,
        ip_rx_ecn, ip_rx_length, ip_rx_identification, ip_rx_flags, ip_rx_fragment_offset, ip_rx_ttl,
        ip_rx_protocol, ip_rx_header_checksum, ip_rx_source_ip, ip_rx_dest_ip, ip_rx_payload.tvalid,
        ip_rx_payload.tdata, ip_rx_payload.tlast, ip_rx_payload.tuser, udp_tx_payload.tready,
        udp_rx_eth_dest_mac, udp_rx_eth_src_mac, udp_rx_eth_type, udp_rx_ip_version, udp_rx_ip_ihl,
        udp_rx_ip_dscp, udp_rx_ip_ecn, udp_rx_ip_length, udp_rx_ip_identification, udp_rx_ip_flags,
        udp_rx_ip_fragment_offset, udp_rx_ip_ttl, udp_rx_ip_protocol, udp_rx_ip_header_checksum,
        udp_rx_ip_source_ip, udp_rx_ip_dest_ip, udp_rx_source_port, udp_rx_dest_port, udp_rx_length,
        udp_rx_checksum, udp_rx_payload.tvalid, udp_rx_payload.tdata, udp_rx_payload.tlast,
        udp_rx_payload.tuser, ip_rx_busy, ip_tx_busy, udp_rx_busy, udp_tx_busy,
        ip_rx_error_header_early_termination, ip_rx_error_payload_early_termination,
        ip_rx_error_invalid_header, ip_rx_error_invalid_checksum, ip_tx_error_payload_early_termination,
        ip_tx_error_arp_failed, udp_rx_error_header_early_termination,
        udp_rx_error_payload_early_termination, udp_tx_error_payload_early_termination
    );
    schedule (
        eth_rx_payload.ptvalid, eth_rx_payload.ptdata, eth_rx_payload.ptlast, eth_rx_payload.ptuser,
        eth_tx_payload.ptready, ip_tx_payload.ptvalid, ip_tx_payload.ptdata, ip_tx_payload.ptlast,
        ip_tx_payload.ptuser, ip_rx_payload.ptready, udp_tx_payload.ptvalid, udp_tx_payload.ptdata,
        udp_tx_payload.ptlast, udp_tx_payload.ptuser, udp_rx_payload.ptready, configure, send_eth_rx,
        accept_eth_tx, send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    ) CF (
        eth_rx_payload.tready, eth_tx_dest_mac, eth_tx_src_mac, eth_tx_eth_type, eth_tx_payload.tvalid,
        eth_tx_payload.tdata, eth_tx_payload.tlast, eth_tx_payload.tuser, ip_tx_payload.tready,
        ip_rx_eth_dest_mac, ip_rx_eth_src_mac, ip_rx_eth_type, ip_rx_version, ip_rx_ihl, ip_rx_dscp,
        ip_rx_ecn, ip_rx_length, ip_rx_identification, ip_rx_flags, ip_rx_fragment_offset, ip_rx_ttl,
        ip_rx_protocol, ip_rx_header_checksum, ip_rx_source_ip, ip_rx_dest_ip, ip_rx_payload.tvalid,
        ip_rx_payload.tdata, ip_rx_payload.tlast, ip_rx_payload.tuser, udp_tx_payload.tready,
        udp_rx_eth_dest_mac, udp_rx_eth_src_mac, udp_rx_eth_type, udp_rx_ip_version, udp_rx_ip_ihl,
        udp_rx_ip_dscp, udp_rx_ip_ecn, udp_rx_ip_length, udp_rx_ip_identification, udp_rx_ip_flags,
        udp_rx_ip_fragment_offset, udp_rx_ip_ttl, udp_rx_ip_protocol, udp_rx_ip_header_checksum,
        udp_rx_ip_source_ip, udp_rx_ip_dest_ip, udp_rx_source_port, udp_rx_dest_port, udp_rx_length,
        udp_rx_checksum, udp_rx_payload.tvalid, udp_rx_payload.tdata, udp_rx_payload.tlast,
        udp_rx_payload.tuser, ip_rx_busy, ip_tx_busy, udp_rx_busy, udp_tx_busy,
        ip_rx_error_header_early_termination, ip_rx_error_payload_early_termination,
        ip_rx_error_invalid_header, ip_rx_error_invalid_checksum, ip_tx_error_payload_early_termination,
        ip_tx_error_arp_failed, udp_rx_error_header_early_termination,
        udp_rx_error_payload_early_termination, udp_tx_error_payload_early_termination
    );
    schedule eth_rx_payload.ptvalid C eth_rx_payload.ptvalid;
    schedule eth_rx_payload.ptvalid CF (
        eth_rx_payload.ptdata, eth_rx_payload.ptlast, eth_rx_payload.ptuser, eth_tx_payload.ptready,
        ip_tx_payload.ptvalid, ip_tx_payload.ptdata, ip_tx_payload.ptlast, ip_tx_payload.ptuser,
        ip_rx_payload.ptready, udp_tx_payload.ptvalid, udp_tx_payload.ptdata, udp_tx_payload.ptlast,
        udp_tx_payload.ptuser, udp_rx_payload.ptready, configure, send_eth_rx, accept_eth_tx, send_ip_tx,
        accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule eth_rx_payload.ptdata C eth_rx_payload.ptdata;
    schedule eth_rx_payload.ptdata CF (
        eth_rx_payload.ptlast, eth_rx_payload.ptuser, eth_tx_payload.ptready, ip_tx_payload.ptvalid,
        ip_tx_payload.ptdata, ip_tx_payload.ptlast, ip_tx_payload.ptuser, ip_rx_payload.ptready,
        udp_tx_payload.ptvalid, udp_tx_payload.ptdata, udp_tx_payload.ptlast, udp_tx_payload.ptuser,
        udp_rx_payload.ptready, configure, send_eth_rx, accept_eth_tx, send_ip_tx, accept_ip_rx,
        send_udp_tx, accept_udp_rx
    );
    schedule eth_rx_payload.ptlast C eth_rx_payload.ptlast;
    schedule eth_rx_payload.ptlast CF (
        eth_rx_payload.ptuser, eth_tx_payload.ptready, ip_tx_payload.ptvalid, ip_tx_payload.ptdata,
        ip_tx_payload.ptlast, ip_tx_payload.ptuser, ip_rx_payload.ptready, udp_tx_payload.ptvalid,
        udp_tx_payload.ptdata, udp_tx_payload.ptlast, udp_tx_payload.ptuser, udp_rx_payload.ptready,
        configure, send_eth_rx, accept_eth_tx, send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule eth_rx_payload.ptuser C eth_rx_payload.ptuser;
    schedule eth_rx_payload.ptuser CF (
        eth_tx_payload.ptready, ip_tx_payload.ptvalid, ip_tx_payload.ptdata, ip_tx_payload.ptlast,
        ip_tx_payload.ptuser, ip_rx_payload.ptready, udp_tx_payload.ptvalid, udp_tx_payload.ptdata,
        udp_tx_payload.ptlast, udp_tx_payload.ptuser, udp_rx_payload.ptready, configure, send_eth_rx,
        accept_eth_tx, send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule eth_tx_payload.ptready C eth_tx_payload.ptready;
    schedule eth_tx_payload.ptready CF (
        ip_tx_payload.ptvalid, ip_tx_payload.ptdata, ip_tx_payload.ptlast, ip_tx_payload.ptuser,
        ip_rx_payload.ptready, udp_tx_payload.ptvalid, udp_tx_payload.ptdata, udp_tx_payload.ptlast,
        udp_tx_payload.ptuser, udp_rx_payload.ptready, configure, send_eth_rx, accept_eth_tx, send_ip_tx,
        accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule ip_tx_payload.ptvalid C ip_tx_payload.ptvalid;
    schedule ip_tx_payload.ptvalid CF (
        ip_tx_payload.ptdata, ip_tx_payload.ptlast, ip_tx_payload.ptuser, ip_rx_payload.ptready,
        udp_tx_payload.ptvalid, udp_tx_payload.ptdata, udp_tx_payload.ptlast, udp_tx_payload.ptuser,
        udp_rx_payload.ptready, configure, send_eth_rx, accept_eth_tx, send_ip_tx, accept_ip_rx,
        send_udp_tx, accept_udp_rx
    );
    schedule ip_tx_payload.ptdata C ip_tx_payload.ptdata;
    schedule ip_tx_payload.ptdata CF (
        ip_tx_payload.ptlast, ip_tx_payload.ptuser, ip_rx_payload.ptready, udp_tx_payload.ptvalid,
        udp_tx_payload.ptdata, udp_tx_payload.ptlast, udp_tx_payload.ptuser, udp_rx_payload.ptready,
        configure, send_eth_rx, accept_eth_tx, send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule ip_tx_payload.ptlast C ip_tx_payload.ptlast;
    schedule ip_tx_payload.ptlast CF (
        ip_tx_payload.ptuser, ip_rx_payload.ptready, udp_tx_payload.ptvalid, udp_tx_payload.ptdata,
        udp_tx_payload.ptlast, udp_tx_payload.ptuser, udp_rx_payload.ptready, configure, send_eth_rx,
        accept_eth_tx, send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule ip_tx_payload.ptuser C ip_tx_payload.ptuser;
    schedule ip_tx_payload.ptuser CF (
        ip_rx_payload.ptready, udp_tx_payload.ptvalid, udp_tx_payload.ptdata, udp_tx_payload.ptlast,
        udp_tx_payload.ptuser, udp_rx_payload.ptready, configure, send_eth_rx, accept_eth_tx, send_ip_tx,
        accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule ip_rx_payload.ptready C ip_rx_payload.ptready;
    schedule ip_rx_payload.ptready CF (
        udp_tx_payload.ptvalid, udp_tx_payload.ptdata, udp_tx_payload.ptlast, udp_tx_payload.ptuser,
        udp_rx_payload.ptready, configure, send_eth_rx, accept_eth_tx, send_ip_tx, accept_ip_rx,
        send_udp_tx, accept_udp_rx
    );
    schedule udp_tx_payload.ptvalid C udp_tx_payload.ptvalid;
    schedule udp_tx_payload.ptvalid CF (
        udp_tx_payload.ptdata, udp_tx_payload.ptlast, udp_tx_payload.ptuser, udp_rx_payload.ptready,
        configure, send_eth_rx, accept_eth_tx, send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule udp_tx_payload.ptdata C udp_tx_payload.ptdata;
    schedule udp_tx_payload.ptdata CF (
        udp_tx_payload.ptlast, udp_tx_payload.ptuser, udp_rx_payload.ptready, configure, send_eth_rx,
        accept_eth_tx, send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule udp_tx_payload.ptlast C udp_tx_payload.ptlast;
    schedule udp_tx_payload.ptlast CF (
        udp_tx_payload.ptuser, udp_rx_payload.ptready, configure, send_eth_rx, accept_eth_tx, send_ip_tx,
        accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule udp_tx_payload.ptuser C udp_tx_payload.ptuser;
    schedule udp_tx_payload.ptuser CF (
        udp_rx_payload.ptready, configure, send_eth_rx, accept_eth_tx, send_ip_tx, accept_ip_rx,
        send_udp_tx, accept_udp_rx
    );
    schedule udp_rx_payload.ptready C udp_rx_payload.ptready;
    schedule udp_rx_payload.ptready CF (
        configure, send_eth_rx, accept_eth_tx, send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule configure C configure;
    schedule configure CF (
        send_eth_rx, accept_eth_tx, send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule send_eth_rx C send_eth_rx;
    schedule send_eth_rx CF (
        accept_eth_tx, send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule accept_eth_tx C accept_eth_tx;
    schedule accept_eth_tx CF (
        send_ip_tx, accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule send_ip_tx C send_ip_tx;
    schedule send_ip_tx CF (
        accept_ip_rx, send_udp_tx, accept_udp_rx
    );
    schedule accept_ip_rx C accept_ip_rx;
    schedule accept_ip_rx CF (
        send_udp_tx, accept_udp_rx
    );
    schedule send_udp_tx C send_udp_tx;
    schedule send_udp_tx CF (
        accept_udp_rx
    );
    schedule accept_udp_rx C accept_udp_rx;
endmodule

module mkUdpComplete#(UdpParameters params)(UdpComplete_ifc);
    let rst_n <- exposeCurrentReset;
    let rst   <- mkResetInverter(rst_n);
    let i_raw <- vMkUdpComplete(rst, params);

    interface Put eth_rx;
        method Action put(EthernetHeader hdr);
            i_raw.send_eth_rx(hdr.dest_mac, hdr.src_mac, hdr.eth_type);
        endmethod
    endinterface
    interface eth_rx_payload = stream_sink(i_raw.eth_rx_payload);
    interface Get eth_tx;
        method ActionValue#(EthernetHeader) get;
            i_raw.accept_eth_tx;
            return EthernetHeader {
                dest_mac: i_raw.eth_tx_dest_mac,
                src_mac:  i_raw.eth_tx_src_mac,
                eth_type: i_raw.eth_tx_eth_type
            };
        endmethod
    endinterface
    interface eth_tx_payload = stream_source(i_raw.eth_tx_payload);
    interface Put ip_tx;
        method Action put(IpTxHeader hdr);
            i_raw.send_ip_tx(hdr.dscp, hdr.ecn, hdr.length, hdr.ttl, hdr.protocol, hdr.source_ip, hdr.dest_ip);
        endmethod
    endinterface
    interface ip_tx_payload = stream_sink(i_raw.ip_tx_payload);
    interface Get ip_rx;
        method ActionValue#(IpRxHeader) get;
            i_raw.accept_ip_rx;
            return IpRxHeader {
                eth_dest_mac:    i_raw.ip_rx_eth_dest_mac,
                eth_src_mac:     i_raw.ip_rx_eth_src_mac,
                eth_type:        i_raw.ip_rx_eth_type,
                version:         i_raw.ip_rx_version,
                ihl:             i_raw.ip_rx_ihl,
                dscp:            i_raw.ip_rx_dscp,
                ecn:             i_raw.ip_rx_ecn,
                length:          i_raw.ip_rx_length,
                identification:  i_raw.ip_rx_identification,
                flags:           i_raw.ip_rx_flags,
                fragment_offset: i_raw.ip_rx_fragment_offset,
                ttl:             i_raw.ip_rx_ttl,
                protocol:        i_raw.ip_rx_protocol,
                header_checksum: i_raw.ip_rx_header_checksum,
                source_ip:       i_raw.ip_rx_source_ip,
                dest_ip:         i_raw.ip_rx_dest_ip
            };
        endmethod
    endinterface
    interface ip_rx_payload = stream_source(i_raw.ip_rx_payload);
    interface Put udp_tx;
        method Action put(UdpTxHeader hdr);
            i_raw.send_udp_tx(hdr.ip_dscp, hdr.ip_ecn, hdr.ip_ttl, hdr.ip_source_ip, hdr.ip_dest_ip, hdr.source_port, hdr.dest_port, hdr.length, hdr.checksum);
        endmethod
    endinterface
    interface udp_tx_payload = stream_sink(i_raw.udp_tx_payload);
    interface Get udp_rx;
        method ActionValue#(UdpRxHeader) get;
            i_raw.accept_udp_rx;
            return UdpRxHeader {
                eth_dest_mac:       i_raw.udp_rx_eth_dest_mac,
                eth_src_mac:        i_raw.udp_rx_eth_src_mac,
                eth_type:           i_raw.udp_rx_eth_type,
                ip_version:         i_raw.udp_rx_ip_version,
                ip_ihl:             i_raw.udp_rx_ip_ihl,
                ip_dscp:            i_raw.udp_rx_ip_dscp,
                ip_ecn:             i_raw.udp_rx_ip_ecn,
                ip_length:          i_raw.udp_rx_ip_length,
                ip_identification:  i_raw.udp_rx_ip_identification,
                ip_flags:           i_raw.udp_rx_ip_flags,
                ip_fragment_offset: i_raw.udp_rx_ip_fragment_offset,
                ip_ttl:             i_raw.udp_rx_ip_ttl,
                ip_protocol:        i_raw.udp_rx_ip_protocol,
                ip_header_checksum: i_raw.udp_rx_ip_header_checksum,
                ip_source_ip:       i_raw.udp_rx_ip_source_ip,
                ip_dest_ip:         i_raw.udp_rx_ip_dest_ip,
                source_port:        i_raw.udp_rx_source_port,
                dest_port:          i_raw.udp_rx_dest_port,
                length:             i_raw.udp_rx_length,
                checksum:           i_raw.udp_rx_checksum
            };
        endmethod
    endinterface
    interface udp_rx_payload = stream_source(i_raw.udp_rx_payload);
    method Action configure(EthernetConfig cfg, Bool clear_cache);
        i_raw.configure(cfg.local_mac, cfg.local_ip, cfg.gateway_ip, cfg.subnet_mask, clear_cache);
    endmethod
    method UdpStatus status = UdpStatus {
        ip_rx_busy:                             i_raw.ip_rx_busy,
        ip_tx_busy:                             i_raw.ip_tx_busy,
        udp_rx_busy:                            i_raw.udp_rx_busy,
        udp_tx_busy:                            i_raw.udp_tx_busy,
        ip_rx_error_header_early_termination:   i_raw.ip_rx_error_header_early_termination,
        ip_rx_error_payload_early_termination:  i_raw.ip_rx_error_payload_early_termination,
        ip_rx_error_invalid_header:             i_raw.ip_rx_error_invalid_header,
        ip_rx_error_invalid_checksum:           i_raw.ip_rx_error_invalid_checksum,
        ip_tx_error_payload_early_termination:  i_raw.ip_tx_error_payload_early_termination,
        ip_tx_error_arp_failed:                 i_raw.ip_tx_error_arp_failed,
        udp_rx_error_header_early_termination:  i_raw.udp_rx_error_header_early_termination,
        udp_rx_error_payload_early_termination: i_raw.udp_rx_error_payload_early_termination,
        udp_tx_error_payload_early_termination: i_raw.udp_tx_error_payload_early_termination
    };
endmodule

endpackage
