`timescale 1ns/1ps

module test_rgmii;
    reg clk = 0;
    reg gtx_clk = 0;
    reg gtx_clk90 = 0;
    reg rst_n = 1;
    always #5 clk = ~clk;
    always #4 gtx_clk = ~gtx_clk;
    initial begin
        #2;
        forever #4 gtx_clk90 = ~gtx_clk90;
    end

    wire tx_clk;
    wire [3:0] tx_data;
    wire tx_ctl;
    reg awvalid = 0, wvalid = 0, bready = 0;
    reg [31:0] awaddr = 0, wdata = 0;
    wire awready, wready, bvalid;
    wire [1:0] bresp;
    reg tx_header_valid = 0;
    wire tx_header_ready;
    reg tx_valid = 0, tx_last = 0;
    reg [7:0] tx_byte = 0;
    wire tx_ready;
    reg rx_header_ready = 0, rx_ready = 0;
    wire rx_header_valid, rx_valid, rx_last, rx_user, rx_keep;
    wire [335:0] rx_header;
    wire [7:0] rx_byte;

    mkTestEthernetRgmii dut (
        .mdio_mdio_i_value(1'b1),
        .CLK(clk), .RST_N(rst_n), .CLK_gtx_clk(gtx_clk),
        .CLK_gtx_clk90(gtx_clk90), .RST_N_gtx_rst_n(rst_n), .CLK_rx_clk(tx_clk),
        .s_rd_arvalid(1'b0), .s_rd_araddr(32'b0), .s_rd_arprot(3'b0), .s_rd_rready(1'b1),
        .s_wr_awvalid(awvalid), .s_wr_awaddr(awaddr), .s_wr_awprot(3'b0), .s_wr_awready(awready),
        .s_wr_wvalid(wvalid), .s_wr_wdata(wdata), .s_wr_wstrb(4'hf), .s_wr_wready(wready),
        .s_wr_bready(bready), .s_wr_bvalid(bvalid), .s_wr_bresp(bresp),
        .tx_header_put({16'd37, 16'd0}), .EN_tx_header_put(tx_header_valid), .RDY_tx_header_put(tx_header_ready),
        .tx_payload_tvalid(tx_valid), .tx_payload_tdata(tx_byte), .tx_payload_tlast(tx_last),
        .tx_payload_tuser(1'b0), .tx_payload_tkeep(1'b1), .tx_payload_tDest(4'b0), .tx_payload_tid(8'b0),
        .tx_payload_tready(tx_ready),
        .EN_rx_header_get(rx_header_ready), .RDY_rx_header_get(rx_header_valid), .rx_header_get(rx_header),
        .rx_payload_tready(rx_ready), .rx_payload_tvalid(rx_valid), .rx_payload_tdata(rx_byte),
        .rx_payload_tlast(rx_last), .rx_payload_tuser(rx_user), .rx_payload_tkeep(rx_keep),
        .pins_rx_data_rxd(tx_data), .pins_rx_data_rx_ctl(tx_ctl),
        .CLK_pins_tx_clk(tx_clk), .pins_tx_data(tx_data), .pins_tx_ctl(tx_ctl)
    );

    task csr_write(input [31:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            awaddr = addr; wdata = data; awvalid = 1; wvalid = 1;
            fork
                begin
                    @(posedge clk);
                    while (!awready) @(posedge clk);
                    @(negedge clk); awvalid = 0;
                end
                begin
                    @(posedge clk);
                    while (!wready) @(posedge clk);
                    @(negedge clk); wvalid = 0;
                end
            join
            bready = 1;
            @(posedge clk);
            while (!bvalid) @(posedge clk);
            if (bresp !== 0) $fatal(1, "CSR write failed at %h: %h", addr, bresp);
            @(negedge clk); bready = 0;
        end
    endtask

    integer idx, cycles;
    initial begin
        #20; rst_n = 0; #200; rst_n = 1;
        csr_write('h08, 'h22334455);
        csr_write('h0c, 'h00000211);
        csr_write('h10, 'hc0a80164);
        csr_write('h14, 'hc0a80101);
        csr_write('h18, 'hffffff00);
        csr_write('h1c, 'hc0a80164);
        csr_write('h20, {16'd5678, 16'd1234});
        csr_write('h28, 1);
        csr_write('h04, 'h00000c03);
        repeat (100) @(posedge clk);

        @(negedge clk); tx_header_valid = 1;
        @(posedge clk);
        while (!tx_header_ready) @(posedge clk);
        @(negedge clk); tx_header_valid = 0;
        for (idx = 0; idx < 37; idx = idx + 1) begin
            tx_valid = 1; tx_byte = idx ^ 'ha5; tx_last = idx == 36;
            @(posedge clk);
            while (!tx_ready) @(posedge clk);
            @(negedge clk);
        end
        tx_valid = 0; tx_last = 0;

        wait(rx_header_valid);
        repeat (50) @(posedge clk);
        @(negedge clk);
        if (rx_header[63:32] !== {16'd1234, 16'd5678} || rx_header[31:16] !== 45 || rx_header[15:0] === 0)
            $fatal(1, "Bad received UDP header: %h", rx_header);
        rx_header_ready = 1;
        @(posedge clk);
        @(negedge clk); rx_header_ready = 0;
        idx = 0; cycles = 0;
        while (idx < 37) begin
            rx_ready = cycles % 3 == 0;
            @(posedge clk);
            if (rx_ready && rx_valid) begin
                if (rx_byte !== (8'ha5 ^ idx[7:0]) || rx_last !== (idx == 36) || rx_user !== 0 || rx_keep !== 1)
                    $fatal(1, "Bad received UDP byte %0d: %h last=%b user=%b", idx, rx_byte, rx_last, rx_user);
                idx = idx + 1;
            end
            cycles = cycles + 1;
            @(negedge clk);
        end
        $display("PASS: AXI-Lite CSR configured UDP through RGMII loopback with independent logic/GTX clocks");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "RGMII loopback timeout");
    end
endmodule
