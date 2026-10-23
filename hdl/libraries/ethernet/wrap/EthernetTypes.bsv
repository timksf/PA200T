package EthernetTypes;

import AXI4_Stream :: *;

// Byte streams: keep = 1, dest = 0, id = 0; user[0] marks a bad frame.
typedef AXI4_Stream_Rd_Fab#(8, 1) EthernetStreamSink_ifc;
typedef AXI4_Stream_Wr_Fab#(8, 1) EthernetStreamSource_ifc;

typedef struct {
    Bit#(48) dest_mac;
    Bit#(48) src_mac;
    Bit#(16) eth_type;
} EthernetHeader deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(6)  dscp;
    Bit#(2)  ecn;
    Bit#(16) length;
    Bit#(8)  ttl;
    Bit#(8)  protocol;
    Bit#(32) source_ip;
    Bit#(32) dest_ip;
} IpTxHeader deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(48) eth_dest_mac;
    Bit#(48) eth_src_mac;
    Bit#(16) eth_type;
    Bit#(4)  version;
    Bit#(4)  ihl;
    Bit#(6)  dscp;
    Bit#(2)  ecn;
    Bit#(16) length;
    Bit#(16) identification;
    Bit#(3)  flags;
    Bit#(13) fragment_offset;
    Bit#(8)  ttl;
    Bit#(8)  protocol;
    Bit#(16) header_checksum;
    Bit#(32) source_ip;
    Bit#(32) dest_ip;
} IpRxHeader deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(6)  ip_dscp;
    Bit#(2)  ip_ecn;
    Bit#(8)  ip_ttl;
    Bit#(32) ip_source_ip;
    Bit#(32) ip_dest_ip;
    Bit#(16) source_port;
    Bit#(16) dest_port;
    Bit#(16) length;
    Bit#(16) checksum;
} UdpTxHeader deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(48) eth_dest_mac;
    Bit#(48) eth_src_mac;
    Bit#(16) eth_type;
    Bit#(4)  ip_version;
    Bit#(4)  ip_ihl;
    Bit#(6)  ip_dscp;
    Bit#(2)  ip_ecn;
    Bit#(16) ip_length;
    Bit#(16) ip_identification;
    Bit#(3)  ip_flags;
    Bit#(13) ip_fragment_offset;
    Bit#(8)  ip_ttl;
    Bit#(8)  ip_protocol;
    Bit#(16) ip_header_checksum;
    Bit#(32) ip_source_ip;
    Bit#(32) ip_dest_ip;
    Bit#(16) source_port;
    Bit#(16) dest_port;
    Bit#(16) length;
    Bit#(16) checksum;
} UdpRxHeader deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(48) local_mac;
    Bit#(32) local_ip;
    Bit#(32) gateway_ip;
    Bit#(32) subnet_mask;
} EthernetConfig deriving(Bits, Eq, FShow);

endpackage
