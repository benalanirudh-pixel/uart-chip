/*
 * Formal properties for sync_fifo (SymbiYosys, bounded model check).
 * The FIFO inputs (clk, rst_n, wr_en, wr_data, rd_en) are free top-level inputs,
 * so the solver tries every possible write/read/reset sequence.
 *
 * An independent "shadow" model counts accepted writes/reads outside the FIFO,
 * so the checks do not just repeat the FIFO's own logic.
 */
`default_nettype none

module fifo_props (
    input wire       clk,
    input wire       rst_n,
    input wire       wr_en,
    input wire [3:0] wr_data,
    input wire       rd_en
);
  localparam WIDTH = 4, AW = 3, DEPTH = 1 << AW;

  wire [WIDTH-1:0] rd_data;
  wire             full, empty;
  wire [   AW:0]   count;

  sync_fifo #(.WIDTH(WIDTH), .AW(AW)) dut (
      .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_data(wr_data),
      .rd_en(rd_en), .rd_data(rd_data), .full(full), .empty(empty), .count(count)
  );

  // first cycle is a reset, so the FIFO starts in a known state
  reg init = 1'b1;
  always @(posedge clk) init <= 1'b0;
  always @* if (init) assume (!rst_n);

  // ---- shadow model: what SHOULD have happened -------------------------------
  wire wr_acc = wr_en & ~full;   // a write that must be accepted
  wire rd_acc = rd_en & ~empty;  // a read that must be accepted

  reg [4:0] sh_count, wr_n, rd_n;  // occupancy, accepted writes, accepted reads
  reg       have;                  // the tracked byte has been written
  reg [WIDTH-1:0] want;            // value of the tracked byte
  (* anyconst *) reg [4:0] k;      // solver picks which byte (by index) to track

  always @(posedge clk) begin
    if (!rst_n) begin
      sh_count <= 5'd0;
      wr_n     <= 5'd0;
      rd_n     <= 5'd0;
      have     <= 1'b0;
    end else begin
      sh_count <= sh_count + {4'd0, wr_acc} - {4'd0, rd_acc};
      wr_n     <= wr_n + {4'd0, wr_acc};
      rd_n     <= rd_n + {4'd0, rd_acc};
      if (wr_acc && wr_n == k) begin
        have <= 1'b1;
        want <= wr_data;
      end
    end
  end

  // ---- previous-cycle values, to check "nothing happened" ---------------------
  reg p_rst_n, p_full, p_empty, p_wr, p_rd;
  reg [AW:0] p_count;
  always @(posedge clk) begin
    p_rst_n <= rst_n;
    p_full  <= full;
    p_empty <= empty;
    p_wr    <= wr_en;
    p_rd    <= rd_en;
    p_count <= count;
  end

  // ---- properties -------------------------------------------------------------
  always @* begin
    if (!init) begin
      // count matches occupancy, never overflows or underflows
      assert (count <= DEPTH);
      assert (count == sh_count);
      assert (full == (count == DEPTH));
      assert (empty == (count == 0));
      assert (!(full && empty));
    end
  end

  always @(posedge clk) begin
    if (!init && p_rst_n) begin
      // never writes when full: a write into a full FIFO changes nothing
      if (p_full && p_wr && !p_rd) assert (count == p_count);
      // never reads when empty: a read of an empty FIFO changes nothing
      if (p_empty && p_rd && !p_wr) assert (count == p_count);
    end
  end

  // data comes out in order: the k-th byte read is the k-th byte written
  always @* begin
    if (!init && rst_n && rd_acc && rd_n == k) begin
      assert (have);
      assert (rd_data == want);
    end
  end

  // ---- cover: show the interesting situations are reachable -------------------
  reg was_full;
  always @(posedge clk) begin
    if (!rst_n) was_full <= 1'b0;
    else if (full) was_full <= 1'b1;
  end
  always @* begin
    if (!init) begin
      cover (full);
      cover (was_full && empty);                  // filled up, then drained
      cover (rst_n && rd_acc && rd_n == k && have);  // tracked byte comes out
      cover (rst_n && wr_n >= 9 && empty);        // pointers have wrapped around
    end
  end
endmodule
