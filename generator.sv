class generator;

    mailbox gen2drv;
    int num;

    function new(mailbox gen2drv, int num = 300);
        this.gen2drv = gen2drv;
        this.num = num;       // increase if needed
    endfunction

    task run();
        transaction t;

        repeat (num) begin
            t = new();

            // Strong constraints to guarantee coverage hits
            assert(t.randomize() with {
                beat_length inside {1,4};
                addr[1:0] == 2'b00;                   // word aligned
                addr[5:2] inside {0,1,2,3};           // hit 4 addr bins
                wrap_en inside {0,1};                 // hit both wrap values
                // Coarse data class distribution (top 2 bits of low byte)
                data[0][7:6] inside {0,1,2,3};
            });

            // Make sure other beats have some data (for burst)
            if (t.beat_length == 4) begin
                for (int i = 1; i < 4; i++) t.data[i] = $urandom();
            end

            // Record stimulus-side coverage (this ensures cross + wrap are sampled)
            t.display("GEN");
            t.sample_cov();

            // Send transaction to driver
            gen2drv.put(t);

            #5; // small spacing
        end
    endtask

endclass




