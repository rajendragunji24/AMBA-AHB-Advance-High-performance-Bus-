class driver;

    mailbox gen2drv;
    virtual ahb_if vif;

    // DUT inputs
    logic [31:0] data_top;
    logic write_top;
    logic [3:0] beat_length;
    logic enb;
    logic [31:0] addr_top;
    logic wrap_enb;

    function new(mailbox gen2drv, virtual ahb_if vif);
        this.gen2drv = gen2drv;
        this.vif = vif;
    endfunction

    task run();
        transaction t;
        forever begin
            gen2drv.get(t);

            t.display("DRV");

            // push words to FIFO
            for (int i=0; i<t.beat_length; i++) begin
                write_top = 1;
                data_top = t.data[i];
                @(posedge vif.HCLK);
                write_top = 0;
            end

            beat_length = t.beat_length;
            addr_top = t.addr;
            wrap_enb = t.wrap_en;

            enb = 1;
            @(posedge vif.HCLK);
            enb = 0;
        end
    endtask

endclass
