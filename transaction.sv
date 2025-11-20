class transaction;

    rand bit [31:0] addr;
    rand bit [31:0] data[4];
    rand int        beat_length;
    rand bit        wrap_en;

    // --------------------------
    // Coverage Group (tool-friendly)
    // --------------------------
    covergroup cg_trans;
        // address lower bits (4 bins)
        addr_lsb: coverpoint addr[5:2];

        // beat length (SINGLE / BURST4)
        beat_len: coverpoint beat_length {
            bins single = {1};
            bins burst4 = {4};
        }

        // wrap enable
        wrap_enb: coverpoint wrap_en {
            bins wrap0 = {0};
            bins wrap1 = {1};
        }

        // coarse data class using top 2 bits of low byte => 4 bins (0..3)
        data_class: coverpoint data[0][7:6];

        // cross coverage: beat_length x wrap_en
        cross_bw: cross beat_length, wrap_en;
    endgroup

    function new();
        cg_trans = new();
    endfunction

    function void sample_cov();
        cg_trans.sample();
    endfunction

    function void display(string tag);
        $display("[%0t] %s TX: addr=0x%08h beat=%0d wrap=%0b data0=0x%08h",
                 $time, tag, addr, beat_length, wrap_en, data[0]);
    endfunction

endclass





