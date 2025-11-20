// master_slave_fixed.sv
`timescale 1ns/1ps

// ------------------------------------------------------------------
// MASTER: master_ahb
// ------------------------------------------------------------------
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

  // state encoding
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
  logic next_HSIZE;
  logic [31:0] next_HWDATA;
  logic [2:0] next_HBURST;
  logic [1:0] next_HTRANS;

  // Derived outputs
  assign fifo_empty = (wr_ptr == rd_ptr);
  assign fifo_full  = ((wr_ptr + 1) == rd_ptr);

  // ----------------------------------------------------------------
  // SINGLE always_ff: FIFO push, pointers, state registers, outputs
  // This block is the single owner for wr_ptr, rd_ptr, addr_internal,
  // count, present_state and AHB output registers.
  // ----------------------------------------------------------------
  always_ff @(posedge clk_master) begin
    if (rst_master) begin
      // reset pointers/state/outputs
      wr_ptr       <= 4'd0;
      rd_ptr       <= 4'd0;
      addr_internal<= 32'h0;
      count        <= 4'd0;
      present_state<= S_IDLE;

      HWRITE       <= 1'b0;
      HSIZE        <= 3'b010;
      HWDATA       <= 32'h0;
      HBURST       <= 3'b000;
      HTRANS       <= 2'b00;

      // clear FIFO memory
      for (int i = 0; i < MEM_DEPTH; i = i + 1) mem[i] <= 32'h0;
    end else begin
      // ---- FIFO push (from testbench/input) ----
      if (write_top) begin
        mem[wr_ptr] <= data_top;
        wr_ptr <= wr_ptr + 1'b1;
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
      // Load base address at the beginning of an address phase
      if (present_state == S_IDLE && next_state == S_WRITE_ADDR) begin
        addr_internal <= addr_top;
        count <= 4'd0;
      end

      // ---- data-phase progression when slave indicates ready ----
      if (present_state == S_WRITE_DATA && HREADY) begin
        if (HBURST == 3'b011) begin // INCR4/WRAP4
          // increment beat counter and read pointer
          count <= count + 1'b1;
          rd_ptr <= rd_ptr + 1'b1;

          // address increment or wrap (4-byte transfers)
          if (!wrap_enb) begin
            addr_internal <= addr_internal + 32'h4;
          end else begin
            // wrap at 16-byte boundary: compute low nibble
            logic [3:0] low_nibble = addr_internal[3:0];
            if (low_nibble == 4'hC) // last beat before wrap (word offset 3)
              addr_internal <= addr_internal - 32'hC; // go to base
            else
              addr_internal <= addr_internal + 32'h4;
          end
        end
        else if (HBURST == 3'b000) begin // SINGLE
          count <= 4'd0; // single completes
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // Combinational next-state + next-output logic
  // Only produces next_* signals consumed by sequential block above.
  // ----------------------------------------------------------------
  always_comb begin
    // defaults
    next_state    = present_state;
    next_HWRITE   = 1'b0;
    next_HSIZE    = 3'b010;
    next_HWDATA   = 32'hx;
    next_HBURST   = 3'b000;
    next_HTRANS   = 2'b00;

    case (present_state)
      S_IDLE: begin
        // start transaction only when enb and HREADY and write requested
        if (enb && HREADY && (wr_ptr != rd_ptr)) begin
          // If testbench wants single write and provided beat_length=1
          if (beat_length == 1 && !wrap_enb) begin
            next_HWRITE = 1'b1;
            next_HBURST = 3'b000; // SINGLE
            next_state = S_WRITE_ADDR;
          end
          // INCR4 or WRAP4
          else if (beat_length == 4) begin
            next_HWRITE = 1'b1;
            next_HBURST = 3'b011; // INCR4 (we treat WRAP via wrap_enb in seq)
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
          next_HWDATA = data_top;  // direct data from testbench for single
          next_HTRANS = 2'b10;
          if (HREADY) next_state = S_IDLE;
        end
        // INCR4/WRAP4 (drive from FIFO memory)
        else if (HBURST == 3'b011) begin
          next_HWDATA = mem[rd_ptr];
          next_HTRANS = 2'b11; // SEQUENTIAL
          // if we completed 4 beats (counter 0..3), next_state -> idle at completion
          if ((count == 4'd3) && HREADY) next_state = S_IDLE;
        end
      end

      default: next_state = S_IDLE;
    endcase
  end

  // HADDR is driven directly by registered addr_internal
  assign HADDR = addr_internal;

endmodule // master_ahb


// ------------------------------------------------------------------
// SLAVE: slave_ahbyt
// ------------------------------------------------------------------
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

  // sample registers (only written in seq block)
  logic [1:0] sampled_HTRANS;
  logic       sampled_HWRITE;
  logic [31:0] sampled_HADDR;

  // next-output signals (combinational)
  logic next_HREADY;
  logic next_HRESP;

  // ----------------------------------------------------------------
  // always_ff: sample inputs, update PS and outputs (single owner)
  // ----------------------------------------------------------------
  always_ff @(posedge HCLK) begin
    if (HRESET) begin
      ps <= SL_IDLE;
      sampled_HTRANS <= 2'b00;
      sampled_HWRITE <= 1'b0;
      sampled_HADDR  <= 32'h0;
      HREADY <= 1'b1;
      HRESP  <= 1'b0;
      HRDATA <= 32'h0;
    end else begin
      // state register
      ps <= ns;

      // sample inputs (registered)
      sampled_HTRANS <= HTRANS;
      sampled_HWRITE <= HWRITE;
      sampled_HADDR  <= HADDR;

      // update outputs from combinational next_* values
      HREADY <= next_HREADY;
      HRESP  <= next_HRESP;

      // if going to write state, capture the HWDATA into HRDATA to present back
      if (ns == SL_WRITE) begin
        HRDATA <= HWDATA;
      end
    end
  end

  // ----------------------------------------------------------------
  // Combinational next-state logic
  // ----------------------------------------------------------------
  always_comb begin
    ns = ps;
    next_HREADY = 1'b1;
    next_HRESP  = 1'b0;

    case (ps)
      SL_IDLE: begin
        next_HREADY = 1'b1;
        ns = SL_SAMPLE;
      end

      SL_SAMPLE: begin
        // If a valid transfer (NONSEQ or SEQ) and HWRITE asserted -> accept and go to write
        if ((HTRANS == 2'b10 || HTRANS == 2'b11) && HWRITE) begin
          ns = SL_WRITE;
        end else begin
          ns = SL_SAMPLE;
        end
      end

      SL_WRITE: begin
        // Present data and be ready; after write, go back to sample
        next_HREADY = 1'b1;
        ns = SL_SAMPLE;
      end

      default: ns = SL_IDLE;
    endcase
  end

endmodule // slave_ahbyt
