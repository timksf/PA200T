package TestEthernetRgmii;

import Clocks       :: *;
import DefaultValue :: *;
import RgmiiMac     :: *;
import UdpRgmiiCsr  :: *;

(* synthesize *)
module mkTestEthernetRgmii#(
    Clock gtx_clk,
    Clock gtx_clk90,
    Reset gtx_rst_n,
    Clock rx_clk
)(UdpRgmiiAxiLite_ifc);
    RgmiiMacParameters mac_params = defaultValue;
    mac_params.target = "GENERIC";
    let                i_eth      <- mkUdpRgmiiAxiLite(defaultValue, mac_params, gtx_clk, gtx_clk90, gtx_rst_n, rx_clk);
    return i_eth;
endmodule

endpackage
