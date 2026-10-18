package PA200T_UART;

import BlueAXI :: *;
import BlueUART :: *;

interface PA200T_UART_ifc;

    (* always_enabled, prefix="uart" *)     method Action rx((* port = "rx" *)Bit#(1) value);
    (* always_enabled, result="uart_tx" *)  method Bit#(1) tx;

    interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_rd;
    interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_wr;

endinterface


module [Module] mkPA200T_UART(PA200T_UART_ifc);

    UartCsr_ifc i_uart <- mkUartCsr(2, 2);

    method rx = i_uart.rx;
    method tx = i_uart.tx; 

    interface s_rd = i_uart.s_rd;
    interface s_wr = i_uart.s_wr;

endmodule


endpackage