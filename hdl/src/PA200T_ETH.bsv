package PA200T_ETH;

import Connectable :: *;
import DefaultValue :: *;

import BlueAXI :: *;
import BlueXLNX :: *;

import Mdio :: *;
import MdioCsr :: *;

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


endpackage