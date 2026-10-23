package EthernetRegs;

import BlueCSRCore   :: *;
import EthernetTypes :: *;
import UDP           :: *;
import RgmiiMac      :: *;
import Mdio          :: *;
import MdioCsr       :: *;

interface EthernetRegs_ifc;
    interface MdioPins_ifc mdio;
    method Bool           phy_reset_n;

    method EthernetConfig network;
    method UdpTxHeader    tx_header(Bit#(16) length, Bit#(16) checksum);
    method Bool           tx_enable;
    method Bool           rx_enable;
    method Bit#(8)        ifg;
    method Bool           clear_arp_cache;
    (* always_ready, always_enabled *)
    method Action         observe(UdpStatus udp, RgmiiMacStatus mac, Bool eth_header_error);
endinterface

module [BlueCSRCtx_t#(32, 32)] ethernet_csrs(EthernetRegs_ifc);
    csr_regmap_def("Ethernet", "UDP/IPv4/ARP and RGMII MAC configuration and status");

    Wire#(UdpStatus)      w_udp          <- mkDWire(unpack(0));
    Wire#(RgmiiMacStatus) w_mac          <- mkDWire(unpack(0));
    Wire#(Bool)           w_eth_error    <- mkDWire(False);

    csr_reg_def('h00, "VERSION", "Register map version");
    csr_reg_rc('h00, Bit#(32)'('h00010000), 0, "VERSION", "Version", "Version 1.0.");

    csr_reg_def('h04, "CONTROL", "MAC controls; disable and drain traffic before changing configuration");
    Reg#(Bool)            rg_tx_enable   <- csr_reg_rw('h04, False, 0, "TX_ENABLE", "TX enable",       "Enable the MAC transmitter.");
    Reg#(Bool)            rg_rx_enable   <- csr_reg_rw('h04, False, 1, "RX_ENABLE", "RX enable",       "Enable the MAC receiver.");
    Reg#(Bit#(8))         rg_ifg         <- csr_reg_rw('h04,    12, 8, "IFG",       "Inter-frame gap", "Gap in byte times; standard Ethernet uses 12.");

    csr_reg_def('h08, "MAC_LOW", "Local MAC bits 31:0");
    Reg#(Bit#(32))        rg_mac_low     <- csr_reg_rw('h08, 0, 0, "VALUE", "Local MAC bits 31:0", "Numeric network-order value.");

    csr_reg_def('h0c, "MAC_HIGH", "Local MAC bits 47:32");
    Reg#(Bit#(16))        rg_mac_high    <- csr_reg_rw('h0c, 0, 0, "VALUE", "Local MAC bits 47:32", "Numeric network-order value.");

    csr_reg_def('h10, "LOCAL_IP", "Local IPv4 address");
    Reg#(Bit#(32))        rg_local_ip    <- csr_reg_rw('h10, 0, 0, "VALUE", "Local IPv4 address", "Numeric network-order value.");

    csr_reg_def('h14, "GATEWAY_IP", "IPv4 gateway");
    Reg#(Bit#(32))        rg_gateway_ip  <- csr_reg_rw('h14, 0, 0, "VALUE", "IPv4 gateway", "Numeric network-order value.");

    csr_reg_def('h18, "SUBNET_MASK", "IPv4 subnet mask");
    Reg#(Bit#(32))        rg_subnet_mask <- csr_reg_rw('h18, 0, 0, "VALUE", "IPv4 subnet mask", "Numeric network-order value.");

    csr_reg_def('h1c, "PEER_IP", "Transmit destination IPv4 address");
    Reg#(Bit#(32))        rg_peer_ip     <- csr_reg_rw('h1c, 0, 0, "VALUE", "Transmit destination IPv4 address", "Numeric network-order value.");

    csr_reg_def('h20, "UDP_PORTS", "Transmit UDP source and destination ports");
    Reg#(Bit#(16))        rg_source_port <- csr_reg_rw('h20, 0,  0, "SOURCE", "Source port",      "UDP source port.");
    Reg#(Bit#(16))        rg_dest_port   <- csr_reg_rw('h20, 0, 16, "DEST",   "Destination port", "UDP destination port.");

    csr_reg_def('h24, "IP_OPTIONS", "Transmit IPv4 options");
    Reg#(Bit#(8))         rg_ttl         <- csr_reg_rw('h24, 64,  0, "TTL",  "Time to live", "IPv4 TTL.");
    Reg#(Bit#(6))         rg_dscp        <- csr_reg_rw('h24,  0,  8, "DSCP", "DSCP",         "IPv4 differentiated services.");
    Reg#(Bit#(2))         rg_ecn         <- csr_reg_rw('h24,  0, 14, "ECN",  "ECN",          "IPv4 explicit congestion notification.");

    csr_reg_def('h28, "ARP_CLEAR", "Any successful write pulses ARP cache clear for one logic-clock cycle");
    csr_reg_wo('h28, Bit#(32)'(0), 0, "COMMAND", "Clear cache", "Write any value to clear the ARP cache.");
    Reg#(Bit#(1))         rg_clear_arp   <- csr_reg_trigw('h28, True);

    csr_reg_def('h2c, "STATUS", "Live MAC speed and protocol busy flags");
    Reg#(Bit#(2))         rg_speed       <- csr_reg_ro('h2c,     0,  0, "SPEED",       "Link speed",  "0: 10M, 1: 100M, 2: 1G. Clock detection, not PHY link status.");
    Reg#(Bool)            rg_ip_rx_busy  <- csr_reg_ro('h2c, False,  8, "IP_RX_BUSY",  "IP RX busy",  "IPv4 receiver busy.");
    Reg#(Bool)            rg_ip_tx_busy  <- csr_reg_ro('h2c, False,  9, "IP_TX_BUSY",  "IP TX busy",  "IPv4 transmitter busy.");
    Reg#(Bool)            rg_udp_rx_busy <- csr_reg_ro('h2c, False, 10, "UDP_RX_BUSY", "UDP RX busy", "UDP receiver busy.");
    Reg#(Bool)            rg_udp_tx_busy <- csr_reg_ro('h2c, False, 11, "UDP_TX_BUSY", "UDP TX busy", "UDP transmitter busy.");

    csr_reg_def('h30, "PROTOCOL_EVENTS", "Sticky events; write one to clear each bit");
    csr_reg_w1c('h30, False, 0, w_udp.ip_rx_error_header_early_termination      ? tagged Valid True : tagged Invalid,   "IP_RX_ERROR_HEADER_EARLY_TERMINATION",     "ip rx error header early termination",     "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h30, False, 1, w_udp.ip_rx_error_payload_early_termination     ? tagged Valid True : tagged Invalid,   "IP_RX_ERROR_PAYLOAD_EARLY_TERMINATION",    "ip rx error payload early termination",    "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h30, False, 2, w_udp.ip_rx_error_invalid_header                ? tagged Valid True : tagged Invalid,   "IP_RX_ERROR_INVALID_HEADER",               "ip rx error invalid header",               "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h30, False, 3, w_udp.ip_rx_error_invalid_checksum              ? tagged Valid True : tagged Invalid,   "IP_RX_ERROR_INVALID_CHECKSUM",             "ip rx error invalid checksum",             "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h30, False, 4, w_udp.ip_tx_error_payload_early_termination     ? tagged Valid True : tagged Invalid,   "IP_TX_ERROR_PAYLOAD_EARLY_TERMINATION",    "ip tx error payload early termination",    "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h30, False, 5, w_udp.ip_tx_error_arp_failed                    ? tagged Valid True : tagged Invalid,   "IP_TX_ERROR_ARP_FAILED",                   "ip tx error arp failed",                   "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h30, False, 6, w_udp.udp_rx_error_header_early_termination     ? tagged Valid True : tagged Invalid,   "UDP_RX_ERROR_HEADER_EARLY_TERMINATION",    "udp rx error header early termination",    "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h30, False, 7, w_udp.udp_rx_error_payload_early_termination    ? tagged Valid True : tagged Invalid,   "UDP_RX_ERROR_PAYLOAD_EARLY_TERMINATION",   "udp rx error payload early termination",   "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h30, False, 8, w_udp.udp_tx_error_payload_early_termination    ? tagged Valid True : tagged Invalid,   "UDP_TX_ERROR_PAYLOAD_EARLY_TERMINATION",   "udp tx error payload early termination",   "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h30, False, 9, w_eth_error                                     ? tagged Valid True : tagged Invalid,   "ETH_HEADER_EARLY_TERMINATION",             "eth header early termination",             "Hardware event wins over a simultaneous software clear.");

    csr_reg_def('h34, "MAC_EVENTS", "Sticky events; write one to clear each bit");
    csr_reg_w1c('h34, False, 0, w_mac.tx_error_underflow    ? tagged Valid True : tagged Invalid,   "TX_ERROR_UNDERFLOW",   "tx error underflow",   "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h34, False, 1, w_mac.tx_fifo_overflow      ? tagged Valid True : tagged Invalid,   "TX_FIFO_OVERFLOW",     "tx fifo overflow",     "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h34, False, 2, w_mac.tx_fifo_bad_frame     ? tagged Valid True : tagged Invalid,   "TX_FIFO_BAD_FRAME",    "tx fifo bad frame",    "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h34, False, 3, w_mac.tx_fifo_good_frame    ? tagged Valid True : tagged Invalid,   "TX_FIFO_GOOD_FRAME",   "tx fifo good frame",   "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h34, False, 4, w_mac.rx_error_bad_frame    ? tagged Valid True : tagged Invalid,   "RX_ERROR_BAD_FRAME",   "rx error bad frame",   "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h34, False, 5, w_mac.rx_error_bad_fcs      ? tagged Valid True : tagged Invalid,   "RX_ERROR_BAD_FCS",     "rx error bad fcs",     "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h34, False, 6, w_mac.rx_fifo_overflow      ? tagged Valid True : tagged Invalid,   "RX_FIFO_OVERFLOW",     "rx fifo overflow",     "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h34, False, 7, w_mac.rx_fifo_bad_frame     ? tagged Valid True : tagged Invalid,   "RX_FIFO_BAD_FRAME",    "rx fifo bad frame",    "Hardware event wins over a simultaneous software clear.");
    csr_reg_w1c('h34, False, 8, w_mac.rx_fifo_good_frame    ? tagged Valid True : tagged Invalid,   "RX_FIFO_GOOD_FRAME",   "rx fifo good frame",   "Hardware event wins over a simultaneous software clear.");

    let i_mdio <- csr_add_context('h40, mdio_csrs);

    rule r_live_status;
        rg_speed       <= w_mac.speed;
        rg_ip_rx_busy  <= w_udp.ip_rx_busy;
        rg_ip_tx_busy  <= w_udp.ip_tx_busy;
        rg_udp_rx_busy <= w_udp.udp_rx_busy;
        rg_udp_tx_busy <= w_udp.udp_tx_busy;
    endrule

    interface mdio = i_mdio.pins;
    method phy_reset_n = i_mdio.phy_reset_n;

    method EthernetConfig network = EthernetConfig {
        local_mac:   {rg_mac_high, rg_mac_low},
        local_ip:    rg_local_ip,
        gateway_ip:  rg_gateway_ip,
        subnet_mask: rg_subnet_mask
    };

    method UdpTxHeader tx_header(Bit#(16) length, Bit#(16) checksum) = UdpTxHeader {
        ip_dscp:      rg_dscp,
        ip_ecn:       rg_ecn,
        ip_ttl:       rg_ttl,
        ip_source_ip: rg_local_ip,
        ip_dest_ip:   rg_peer_ip,
        source_port:  rg_source_port,
        dest_port:    rg_dest_port,
        length:       length,
        checksum:     checksum
    };

    method tx_enable       = rg_tx_enable;
    method rx_enable       = rg_rx_enable;
    method ifg             = rg_ifg;
    method clear_arp_cache = unpack(rg_clear_arp);

    method Action observe(UdpStatus udp, RgmiiMacStatus mac, Bool eth_header_error);
        w_udp       <= udp;
        w_mac       <= mac;
        w_eth_error <= eth_header_error;
    endmethod
endmodule

endpackage
