class monitor;

    mailbox mon2scb;
    virtual ahb_if vif;

    transaction last_tr;

    function new(mailbox mon2scb, virtual ahb_if vif);
        this.mon2scb = mon2scb;
        this.vif = vif;
    endfunction

    task run();
        transaction t;

        forever begin
            @(posedge vif.HCLK);

            if ((vif.HTRANS == 2'b10 || vif.HTRANS == 2'b11) && vif.HWRITE && vif.HREADY) begin
                t = new();
                t.addr = vif.HADDR;
                t.data[0] = vif.HWDATA;

                // derive beat_length from HBURST: treat 3'b011 as 4-beat
                if (vif.HBURST == 3'b011) t.beat_length = 4;
                else t.beat_length = 1;

                // wrap_en is not observable on the bus in this simple setup.
                // We leave t.wrap_en unset here (generator already sampled wrap_en).
                // If you add a sideband signal for wrap, capture it here.

                t.display("MON");
                t.sample_cov();   // sample what monitor can observe (addr, beat, data_class)
                last_tr = t;

                mon2scb.put(t);
            end
        end
    endtask

endclass


