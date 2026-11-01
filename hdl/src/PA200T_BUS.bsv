package PA200T_BUS;

import DefaultValue :: *;
import GetPut :: *;

import BlueAXI :: *;
import Axi4Lite :: *;
import Axi4LiteAddrMap :: *;
import Axi4LiteRegSlice :: *;
import BlueAddrMap :: *;

// UART stays at 0 so the UART helpers keep their addresses. Without the UDP subsystem, ETH and UDP_TRAFFIC are backed by mkPA200T_ErrorSlave.
module [AddrMapCtx_t#(32, Axi4LiteSlaveFab_ifc#(32, 32))] pa200t_addr_map#(
    Axi4LiteSlaveFab_ifc#(32, 32) uart,
    Axi4LiteSlaveFab_ifc#(32, 32) mdio,
    Axi4LiteSlaveFab_ifc#(32, 32) eth,
    Axi4LiteSlaveFab_ifc#(32, 32) traffic
)(Empty);
    addr_map_def("PA200T AXI4-Lite");
    addr_map_target('h0000_0000, 'h1000, "UART",        uart);
    addr_map_target('h0000_1000, 'h1000, "MDIO",        mdio);
    addr_map_target('h0000_2000, 'h1000, "ETH",         eth);
    addr_map_target('h0000_3000, 'h1000, "UDP_TRAFFIC", traffic);
endmodule

// The request slice lets the address decode start at a register. Targets are BlueCSR peripherals that decode from offset 0, so they see region-local addresses.
module [Module] mkPA200T_Bus#(
    Axi4LiteSlaveFab_ifc#(32, 32) uart,
    Axi4LiteSlaveFab_ifc#(32, 32) mdio,
    Axi4LiteSlaveFab_ifc#(32, 32) eth,
    Axi4LiteSlaveFab_ifc#(32, 32) traffic
)(Axi4LiteSlaveFab_ifc#(32, 32));

    Axi4LiteBusCfg_t cfg = defaultValue;
    cfg.upstream_cut = axi4_lite_slice_request;
    cfg.local_addr   = True;

    //collected once, the documentation and the bus share it
    AddrMapCollected_t#(4, Axi4LiteSlaveFab_ifc#(32, 32), Empty) addr_map <- collect_addr_map(pa200t_addr_map(uart, mdio, eth, traffic));
    messageM(doc_addr_map(addr_map).text);

    AddrMapBus_ifc#(4, Axi4LiteSlaveFab_ifc#(32, 32), Empty) i_bus <- mkAddrMapBus(cfg, addr_map);
    return i_bus.up;
endmodule

// Stands in for a peripheral that is not built, every access returns DECERR like unmapped space.
module [Module] mkPA200T_ErrorSlave(Axi4LiteSlaveFab_ifc#(32, 32));
    AXI4_Lite_Slave_Rd#(32, 32) i_rd <- mkAXI4_Lite_Slave_Rd(2);
    AXI4_Lite_Slave_Wr#(32, 32) i_wr <- mkAXI4_Lite_Slave_Wr(2);

    rule r_read;
        let req <- i_rd.request.get;
        i_rd.response.put(AXI4_Lite_Read_Rs_Pkg { data: 0, resp: DECERR });
    endrule

    rule r_write;
        let req <- i_wr.request.get;
        i_wr.response.put(AXI4_Lite_Write_Rs_Pkg { resp: DECERR });
    endrule

    return axi4_lite_slave_fab(i_rd.fab, i_wr.fab);
endmodule

endpackage
