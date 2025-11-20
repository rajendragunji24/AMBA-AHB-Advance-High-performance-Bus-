`include "transaction.sv"
`include "generator.sv"
`include "driver.sv"
`include "monitor.sv"
`include "scoreboard.sv"

class environment;

    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    mailbox gen2drv;
    mailbox mon2scb;

    virtual ahb_if vif;

    function new(virtual ahb_if vif);
        this.vif = vif;
        gen2drv = new();
        mon2scb = new();

        // create with many transactions to converge coverage
        gen = new(gen2drv, 300);
        drv = new(gen2drv, vif);
        mon = new(mon2scb, vif);
        scb = new(mon2scb);
    endfunction

    task run();
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_none
    endtask

    function void print_cov();
        // Print global coverage summary (tool-dependent but widely supported)
        $display("\n===== COVERAGE SUMMARY =====");
        $display("GLOBAL COVERAGE = %0.2f%%", $get_coverage());

        if (mon.last_tr != null) begin
            $display("Last observed transaction covergroup coverage: %0.2f%%",
                     mon.last_tr.cg_trans.get_inst_coverage());
        end else begin
            $display("No transactions observed by monitor.");
        end
        $display("============================\n");
    endfunction

endclass
