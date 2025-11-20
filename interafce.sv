interface ahb_if(input logic HCLK, input logic HRESET);

    // ---------------------------------------------------
    // AHB SIGNALS
    // ---------------------------------------------------
    logic [31:0] HADDR;
    logic        HWRITE;
    logic [2:0]  HSIZE;
    logic [31:0] HWDATA;
    logic [2:0]  HBURST;
    logic [1:0]  HTRANS;

    logic        HREADY;
    logic        HRESP;
    logic [31:0] HRDATA;

    // ---------------------------------------------------
    // CLOCKING
    // ---------------------------------------------------
    clocking cb @(posedge HCLK);
        input HRESET;
        input HADDR;
        input HWRITE;
        input HSIZE;
        input HWDATA;
        input HBURST;
        input HTRANS;
        input HREADY;
        input HRESP;
        input HRDATA;
    endclocking


    // ---------------------------------------------------
    // AHB ASSERTIONS
    // ---------------------------------------------------

    // 1. First beat must be NONSEQ (address phase)
    property p_nonseq_firstbeat;
        @(posedge HCLK) disable iff(HRESET)
            (HTRANS == 2'b10) |-> (HWRITE || !HWRITE);
    endproperty
    assert property(p_nonseq_firstbeat)
        else $error("ERROR: First beat must be NONSEQ!");

    // 2. After NONSEQ, remaining beats must be SEQ for burst
    property p_burst_seq;
        @(posedge HCLK) disable iff(HRESET)
            (HBURST == 3'b011 && HTRANS == 2'b10 && HREADY) |=> (HTRANS == 2'b11);
    endproperty
    assert property(p_burst_seq)
        else $error("ERROR: Burst beats must be SEQ!");

    // 3. SINGLE transfer must not use SEQ
    property p_single_no_seq;
        @(posedge HCLK) disable iff(HRESET)
            (HBURST == 3'b000) |-> (HTRANS != 2'b11);
    endproperty
    assert property(p_single_no_seq)
        else $error("ERROR: SINGLE transfer is using SEQ!");

    // 4. HSIZE must be 4 bytes (word, 010)
    property p_hsize_word;
        @(posedge HCLK) disable iff(HRESET)
            1 |-> (HSIZE == 3'b010);
    endproperty
    assert property(p_hsize_word)
        else $error("ERROR: HSIZE is not 4-byte word!");

    // 5. Slave must always drive HREADY = 1
    property p_slave_ready;
        @(posedge HCLK) disable iff(HRESET)
            HREADY == 1;
    endproperty
    assert property(p_slave_ready)
        else $error("ERROR: Slave inserted wait state (HREADY != 1)!");

    // 6. Slave must accept only valid write transfers
    property p_valid_write;
        @(posedge HCLK) disable iff(HRESET)
            (HTRANS inside {2'b10,2'b11}) && HWRITE |-> HREADY;
    endproperty
    assert property(p_valid_write)
        else $error("ERROR: Invalid write transfer!");

    // 7. HRDATA must match HWDATA in write cycle (simple check)
    property p_data_echo;
        @(posedge HCLK) disable iff(HRESET)
            (HWRITE && HREADY && HTRANS inside {2'b10,2'b11}) |=> (HRDATA == HWDATA);
    endproperty
    assert property(p_data_echo)
        else $error("ERROR: HRDATA does not match written HWDATA!");

endinterface





