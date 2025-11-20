`include "interface.sv"
`include "environment.sv"

module top_tb;

    logic clk, rst;

    // ---------------------------------------------------
    // Clock Generation
    // ---------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ---------------------------------------------------
    // Reset
    // ---------------------------------------------------
    initial begin
        rst = 1;
        #20 rst = 0;
    end

    // ---------------------------------------------------
    // Waveform Dump
    // ---------------------------------------------------
    initial begin
        $dumpfile("ahb_wave.vcd");   // waveform file
        $dumpvars(0, top_tb);        // dump everything in tb scope
    end

    // ---------------------------------------------------
    // Interface
    // ---------------------------------------------------
    ahb_if ahb(clk, rst);

    // DUT I/O signals
    logic [31:0] data_top, addr_top;
    logic write_top, enb, wrap_enb;
    logic [3:0] beat_length;

    // ---------------------------------------------------
    // Instantiate DUT : AHB Master
    // ---------------------------------------------------
    master_ahb master_u(
        .clk_master(clk),
        .rst_master(rst),
        .HREADY(ahb.HREADY),
        .HRDATA(ahb.HRDATA),

        .data_top(data_top),
        .write_top(write_top),
        .beat_length(beat_length),
        .enb(enb),
        .addr_top(addr_top),
        .wrap_enb(wrap_enb),

        .HADDR(ahb.HADDR),
        .HWRITE(ahb.HWRITE),
        .HSIZE(ahb.HSIZE),
        .HWDATA(ahb.HWDATA),
        .HBURST(ahb.HBURST),
        .HTRANS(ahb.HTRANS),

        .fifo_empty(),
        .fifo_full()
    );

    // ---------------------------------------------------
    // Instantiate DUT : AHB Slave
    // ---------------------------------------------------
    slave_ahbyt slave_u(
        .HCLK(clk),
        .HRESET(rst),
        .HADDR(ahb.HADDR),
        .HWRITE(ahb.HWRITE),
        .HSIZE(ahb.HSIZE),
        .HBURST(ahb.HBURST),
        .HTRANS(ahb.HTRANS),
        .HWDATA(ahb.HWDATA),
        .HREADY(ahb.HREADY),
        .HRESP(ahb.HRESP),
        .HRDATA(ahb.HRDATA)
    );

    // ---------------------------------------------------
    // Environment + TEST SCENARIOS
    // ---------------------------------------------------
    environment env;

    initial begin
        env = new(ahb);
        env.run();  // your original environment first

        // ---------------------------------------------------
        // MANUAL TEST SEQUENCES FOR WAVEFORMS
        // ---------------------------------------------------
        #50;
        $display("\n========== TESTCASE 1: SINGLE WRITE ==========");

        addr_top     = 32'h0000_0100;
        data_top     = 32'hAABB_CCDD;
        write_top    = 1;  #10; write_top = 0;
        beat_length  = 1;
        wrap_enb     = 0;
        enb          = 1;  #10; enb = 0;

        #200;

        // ---------------------------------------------------
        $display("\n========== TESTCASE 2: INCR4 BURST WRITE ==========");

        addr_top = 32'h0000_0200;

        data_top = 32'h1111_0001; write_top = 1; #10;
        data_top = 32'h2222_0002; #10;
        data_top = 32'h3333_0003; #10;
        data_top = 32'h4444_0004; #10; write_top = 0;

        beat_length = 4;
        wrap_enb = 0;
        enb = 1; #10; enb = 0;

        #300;

        // ---------------------------------------------------
        $display("\n========== TESTCASE 3: WRAP4 BURST WRITE ==========");

        addr_top = 32'h0000_00FC;

        data_top = 32'hAAAA_0001; write_top = 1; #10;
        data_top = 32'hBBBB_0002; #10;
        data_top = 32'hCCCC_0003; #10;
        data_top = 32'hDDDD_0004; #10; write_top = 0;

        beat_length = 4;
        wrap_enb = 1;
        enb = 1; #10; enb = 0;

        #300;

        // ---------------------------------------------------
        // PRINT COVERAGE (your original code)
        // ---------------------------------------------------
        env.print_cov();

        $display("\n========== ALL TESTCASES COMPLETED ==========");
        $finish;
    end

endmodule
