// master_slave_fixed.sv
`timescale 1ns/1ps

// --------------------- corrected master_ahb (key fixes) --------------------
module master_ahb(
  input  logic        clk_master,
  input  logic        rst_master,
  input  logic        HREADY,         // from slave
  input  logic [31:0] HRDATA,         // from slave

  // user inputs
  input  logic [31:0] data_top,
  input  logic        write_top,      // push into FIFO (testbench)
  input  logic [3:0]  beat_length,    // 1 or 4
  input  logic        enb,            // start transaction
  input  logic [31:0] addr_top,
  input  logic        wrap_enb,       // wrap burst enable

  // AHB outputs
  output logic [31:0] HADDR,
  output logic        HWRITE,
  output logic [2:0]  HSIZE,
  output logic [31:0] HWDATA,
  output logic [2:0]  HBURST,
  output logic [1:0]  HTRANS,

  // fifo status
  output logic fifo_empty,
  output logic fifo_full
);

  typedef enum logic [2:0] {
    S_IDLE                = 3'b000,
    S_WRITE_ADDR          = 3'b001,
    S_WRITE_DATA          = 3'b010
  } state_t;

  state_t present_state, next_state;

  // Registers (single owners)
  logic [31:0] addr_internal;
  logic [3:0]  count;        // beat counter 0..3
  logic [3:0]  wr_ptr;
  logic [3:0]  rd_ptr;
  localparam int MEM_DEPTH = 15;
  logic [31:0] mem [0:MEM_DEPTH-1];

  // Outputs are registered as well (driven from next_* in seq block)
  logic next_HWRITE;
  logic [2:0] next_HSIZE;               // <--- FIXED: 3-bit
  logic [31:0] next_HWDATA;
  logic [2:0] next_HBURST;
  logic [1:0] next_HTRANS;

  // FIFO count to avoid pointer race/X issues
  logic [4:0] fifo_count; // can hold 0..MEM_DEPTH

  // Derived outputs (use fifo_count)
  assign fifo_empty = (fifo_count == 0);
  assign fifo_full  = (fifo_count >= MEM_DEPTH-1); // leave one slot if circular pointer scheme

  // ----------------------------------------------------------------
  // Sequential block: FIFO push/pop, pointers, state registers, outputs
  // ----------------------------------------------------------------
  always_ff @(posedge clk_master or posedge rst_master) begin
    if (rst_master) begin
      // reset pointers/state/outputs
      wr_ptr        <= 4'd0;
      rd_ptr        <= 4'd0;
      addr_internal <= 32'h0;
      count         <= 4'd0;
      present_state <= S_IDLE;

      HWRITE        <= 1'b0;
      HSIZE         <= 3'b010;
      HWDATA        <= 32'h0;
      HBURST        <= 3'b000;
      HTRANS        <= 2'b00;

      fifo_count    <= 5'd0;

      // clear FIFO memory
      for (int i = 0; i < MEM_DEPTH; i = i + 1) mem[i] <= 32'h0;
    end else begin
      // ---- FIFO push (synchronous capture) ----
      if (write_top && (fifo_count < MEM_DEPTH)) begin
        mem[wr_ptr] <= data_top;
        wr_ptr <= wr_ptr + 1'b1;
        fifo_count <= fifo_count + 1'b1;
      end

      // ---- state update ----
      present_state <= next_state;

      // ---- output regs update from combinational decisions ----
      HWRITE <= next_HWRITE;
      HSIZE  <= next_HSIZE;
      HWDATA <= next_HWDATA;
      HBURST <= next_HBURST;
      HTRANS <= next_HTRANS;

      // ---- address/load/start behavior ----
      if (present_state == S_IDLE && next_state == S_WRITE_ADDR) begin
        addr_internal <= addr_top;
        count <= 4'd0;
      end

      // ---- data-phase progression when slave indicates ready ----
      if (present_state == S_WRITE_DATA && HREADY) begin
        // If we are issuing a burst, consume one element from FIFO (if available)
        if (HBURST == 3'b011) begin // INCR4/WRAP4
          if (fifo_count > 0) begin
            rd_ptr <= rd_ptr + 1'b1;
            fifo_count <= fifo_count - 1'b1;
          end
          // increment beat counter and update address (wrap/increment)
          count <= count + 1'b1;
          if (!wrap_enb) begin
            addr_internal <= addr_internal + 32'h4;
          end else begin
            logic [3:0] low_nibble = addr_internal[3:0];
            if (low_nibble == 4'hC) // last beat before wrap (word offset 3)
              addr_internal <= addr_internal - 32'hC; // go to base
            else
              addr_internal <= addr_internal + 32'h4;
          end
        end else if (HBURST == 3'b000) begin // SINGLE
          // nothing to pop for single (we will directly use mem/ or capture data_top earlier)
          count <= 4'd0; // single completes
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // Combinational next-state + next-output logic
  // ----------------------------------------------------------------
  always_comb begin
    // defaults
    next_state    = present_state;
    next_HWRITE   = 1'b0;
    next_HSIZE    = 3'b010;
    next_HWDATA   = 32'h0;                // <-- avoid X default
    next_HBURST   = 3'b000;
    next_HTRANS   = 2'b00;

    case (present_state)
      S_IDLE: begin
        // start transaction only when enb and HREADY and there is data in FIFO
        if (enb && HREADY && (fifo_count > 0)) begin
          if (beat_length == 1 && !wrap_enb) begin
            next_HWRITE = 1'b1;
            next_HBURST = 3'b000; // SINGLE
            next_state = S_WRITE_ADDR;
          end else if (beat_length == 4) begin
            next_HWRITE = 1'b1;
            next_HBURST = 3'b011; // INCR4
            next_state = S_WRITE_ADDR;
          end
        end
      end

      S_WRITE_ADDR: begin
        next_HWRITE = 1'b1;
        next_HSIZE  = 3'b010;  // 4 bytes
        next_HTRANS = 2'b10;   // NONSEQ for address phase
        // Move to data phase next
        next_state = S_WRITE_DATA;
      end

      S_WRITE_DATA: begin
        next_HWRITE = 1'b1;
        next_HSIZE  = 3'b010;

        // SINGLE
        if (HBURST == 3'b000) begin
          // For safety, use the FIFO entry if available; else use data_top
          if (fifo_count > 0)
            next_HWDATA = mem[rd_ptr];  // pop will occur in sequential block when HREADY
          else
            next_HWDATA = data_top;
          next_HTRANS = 2'b10;
          if (HREADY) next_state = S_IDLE;
        end
        // INCR4/WRAP4 (drive from FIFO memory only if data present)
        else if (HBURST == 3'b011) begin
          if (fifo_count > 0) begin
            next_HWDATA = mem[rd_ptr];
          end else begin
            next_HWDATA = 32'h0; // safe fallback, prevents X
          end
          next_HTRANS = 2'b11; // SEQUENTIAL
          if ((count == 4'd3) && HREADY) next_state = S_IDLE;
        end
      end

      default: next_state = S_IDLE;
    endcase
  end

  // HADDR is driven directly by registered addr_internal
  assign HADDR = addr_internal;

endmodule
// --------------------- end corrected master_ahb --------------------------

module slave_ahbyt(
  input  logic        HCLK,
  input  logic        HRESET,
  input  logic [31:0] HADDR,
  input  logic        HWRITE,
  input  logic [2:0]  HSIZE,
  input  logic [2:0]  HBURST,
  input  logic [1:0]  HTRANS,
  input  logic [31:0] HWDATA,
  output logic        HREADY,
  output logic        HRESP,
  output logic [31:0] HRDATA
);

  typedef enum logic [1:0] {
    SL_IDLE   = 2'b00,
    SL_SAMPLE = 2'b01,
    SL_WRITE  = 2'b10
  } sl_state_t;

  sl_state_t ps, ns;

  logic [1:0]  sampled_HTRANS;
  logic        sampled_HWRITE;
  logic [31:0] sampled_HADDR;
  logic [31:0] sampled_HWDATA;

  logic next_HREADY, next_HRESP;

  always_ff @(posedge HCLK or posedge HRESET) begin
    if (HRESET) begin
      ps <= SL_IDLE;
      sampled_HTRANS <= 2'b00;
      sampled_HWRITE <= 1'b0;
      sampled_HADDR  <= 32'h0;
      sampled_HWDATA <= 32'h0;
      HREADY <= 1'b1;
      HRESP  <= 1'b0;
      HRDATA <= 32'h0;
    end else begin
      ps <= ns;

      sampled_HTRANS <= HTRANS;
      sampled_HWRITE <= HWRITE;
      sampled_HADDR  <= HADDR;
      sampled_HWDATA <= HWDATA;

      HREADY <= next_HREADY;
      HRESP  <= next_HRESP;

      if (ns == SL_WRITE)
        HRDATA <= sampled_HWDATA;
    end
  end

  always_comb begin
    ns = ps;
    next_HREADY = 1;
    next_HRESP  = 0;

    case (ps)
      SL_IDLE: begin
        ns = SL_SAMPLE;
      end

      SL_SAMPLE: begin
        // Valid AHB address phase
        if ((HTRANS == 2'b10 || HTRANS == 2'b11) &&
            (HWRITE == 1'b1)) begin
          ns = SL_WRITE;
        end
      end

      SL_WRITE: begin
        ns = SL_SAMPLE;
      end
    endcase
  end
endmodule
