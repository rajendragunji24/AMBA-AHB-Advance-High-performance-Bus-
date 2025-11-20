class scoreboard;

    mailbox mon2scb;

    function new(mailbox mon2scb);
        this.mon2scb = mon2scb;
    endfunction

    task run();
        transaction t;
        forever begin
            mon2scb.get(t);
            $display("[SCB] Observed Write @ addr=%h data=%h",
                     t.addr, t.data[0]);
        end
    endtask

endclass
