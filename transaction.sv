class transaction;

    // -----------------------------------------------------
    // Randomizable stimulus fields
    // -----------------------------------------------------
    rand bit [31:0] addr;
    rand bit [31:0] data[4];
    rand int        beat_length;     // 1 or 4
    rand bit        wrap_en;         // 0 or 1

    // -----------------------------------------------------
    // Coverage Group
    // -----------------------------------------------------
 covergroup cg_trans;

    // Only bins for ADDRESSES YOU USE
    addr_lsb : coverpoint addr[5:2] {
        bins addr3  = {3};
        bins addr4  = {4};
        bins addr8  = {8};
        bins addr12 = {12};
    }

    beat_len : coverpoint beat_length {
        bins single = {1};
        bins burst4 = {4};
    }

    wrap_enb : coverpoint wrap_en {
        bins wrap0 = {0};
        bins wrap1 = {1};
    }

    data_class : coverpoint data[0][7:6] {
        bins c0 = {0};
        bins c1 = {1};
        bins c2 = {2};
        bins c3 = {3};
    }

    cross_bw : cross beat_length, wrap_en;

endgroup


    // -----------------------------------------------------
    // Constructor
    // -----------------------------------------------------
    function new();
        cg_trans = new();
    endfunction

    // -----------------------------------------------------
    // Coverage sampler function
    // -----------------------------------------------------
    function void sample_cov();
        cg_trans.sample();
    endfunction

    // -----------------------------------------------------
    // Display function (debug prints)
    // -----------------------------------------------------
    function void display(string tag);
        $display("[%0t] %s TX:", $time, tag);
        $display("  addr       = 0x%08h", addr);
        $display("  beat_length= %0d", beat_length);
        $display("  wrap_en    = %0b", wrap_en);
        $display("  data0      = 0x%08h", data[0]);
    endfunction

endclass






