`include "interface.sv"
`include "environment.sv"

module top_tb;

    logic clk, rst;
    transaction tr;

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
        #30 rst = 0;
    end

    // ---------------------------------------------------
    // Dump
    // ---------------------------------------------------
    initial begin
        $dumpfile("ahb_wave.vcd");
        $dumpvars(0, top_tb);
    end

    // ---------------------------------------------------
    // Interface
    // ---------------------------------------------------
    ahb_if ahb(clk, rst);

    // TB signals
    logic [31:0] data_top, addr_top;
    logic write_top, enb, wrap_enb;
    logic [3:0] beat_length;

    // ---------------------------------------------------
    // MASTER
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
        .HTRANS(ahb.HTRANS)
    );

    // ---------------------------------------------------
    // SLAVE
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

    environment env;

    // ---------------------------------------------------
    // TEST SEQUENCES FOR 100% COVERAGE
    // ---------------------------------------------------
    initial begin
        env = new(ahb);
        tr  = new();

        data_top    = 32'h0;
        addr_top    = 32'h0;
        write_top   = 0;
        enb         = 0;
        wrap_enb    = 0;
        beat_length = 0;

        @(negedge rst); #20;

        // ==========================================================
        // TESTCASE-1 : SINGLE (class=3)
        // ==========================================================
        @(posedge clk);
        addr_top    = 32'h0000_0100;
        beat_length = 1;
        wrap_enb    = 0;

        @(posedge clk);
        write_top = 1; data_top = 32'hAABB_CCDD; // class=3

        @(posedge clk);
        write_top = 0;

        @(posedge clk); enb = 1;
        @(posedge clk); enb = 0;

        @(posedge clk);
        tr.addr        = addr_top;
        tr.data[0]     = 32'hAABB_CCDD;
        tr.beat_length = 1;
        tr.wrap_en     = 0;
        tr.sample_cov();


        // ==========================================================
        // TESTCASE-2 : INCR4 (class=0)
        // ==========================================================
        @(posedge clk);
        addr_top    = 32'h0000_0200;
        beat_length = 4;
        wrap_enb    = 0;

        @(posedge clk); write_top = 1; data_top = 32'h1111_0001; // class=0
        @(posedge clk);              data_top = 32'h2222_0002;
        @(posedge clk);              data_top = 32'h3333_0003;
        @(posedge clk);              data_top = 32'h4444_0004;
        @(posedge clk); write_top = 0;

        @(posedge clk); enb = 1;
        @(posedge clk); enb = 0;

        @(posedge clk);
        tr.addr        = 32'h0000_0200;
        tr.data[0]     = 32'h1111_0001;
        tr.beat_length = 4;
        tr.wrap_en     = 0;
        tr.sample_cov();


        // ==========================================================
        // TESTCASE-3 : WRAP4 (class=0)
        // ==========================================================
        @(posedge clk);
        addr_top    = 32'h0000_00FC;
        beat_length = 4;
        wrap_enb    = 1;

        @(posedge clk); write_top = 1; data_top = 32'hAAAA_0001; // class=0
        @(posedge clk);              data_top = 32'hBBBB_0002;
        @(posedge clk);              data_top = 32'hCCCC_0003;
        @(posedge clk);              data_top = 32'hDDDD_0004;
        @(posedge clk); write_top = 0;

        @(posedge clk); enb = 1;
        @(posedge clk); enb = 0;

        @(posedge clk);
        tr.addr        = 32'h0000_00FC;
        tr.data[0]     = 32'hAAAA_0001;
        tr.beat_length = 4;
        tr.wrap_en     = 1;
        tr.sample_cov();


        // ==========================================================
        // TESTCASE-4 : SINGLE + WRAP=1  (class=1)
        // ==========================================================
        @(posedge clk);
        addr_top    = 32'h0000_0300;  // New addr_lsb
        beat_length = 1;
        wrap_enb    = 1;

        @(posedge clk); write_top = 1; data_top = 32'h1234_40FF; // class=1
        @(posedge clk); write_top = 0;

        @(posedge clk); enb = 1;
        @(posedge clk); enb = 0;

        @(posedge clk);
        tr.addr        = addr_top;
        tr.data[0]     = 32'h1234_40FF;
        tr.beat_length = 1;
        tr.wrap_en     = 1;
        tr.sample_cov();


        // ==========================================================
        // TESTCASE-5 : SINGLE + WRAP=0  (class=2)
        // ==========================================================
        @(posedge clk);
        addr_top    = 32'h0000_0400;  // Another addr_lsb value
        beat_length = 1;
        wrap_enb    = 0;

        @(posedge clk); write_top = 1; data_top = 32'h5678_80AA; // class=2
        @(posedge clk); write_top = 0;

        @(posedge clk); enb = 1;
        @(posedge clk); enb = 0;

        @(posedge clk);
        tr.addr        = addr_top;
        tr.data[0]     = 32'h5678_80AA;
        tr.beat_length = 1;
        tr.wrap_en     = 0;
        tr.sample_cov();


        // ==========================================================
        // COVERAGE REPORT
        // ==========================================================
        #20;
        $display("\n================ COVERAGE REPORT =================");
        $display("Total Functional Coverage = %0.2f %%", $get_coverage());
        $display("===================================================\n");

        $display("========== ALL TESTCASES COMPLETED ==========");
        $finish;
    end

endmodule








