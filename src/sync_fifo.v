/*
 * Copyright (c) 2026 anirudh
 * SPDX-License-Identifier: Apache-2.0
 *
 * sync_fifo: single-clock FIFO, depth = 2**AW, first-word-fall-through read
 * (rd_data always shows the oldest entry). A write when full and a read when
 * empty are ignored, so the FIFO can never overflow or underflow.
 */
`default_nettype none

module sync_fifo #(
    parameter WIDTH = 8,
    parameter AW    = 3     // depth = 2**AW
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             wr_en,
    input  wire [WIDTH-1:0] wr_data,
    input  wire             rd_en,
    output wire [WIDTH-1:0] rd_data,
    output wire             full,
    output wire             empty,
    output reg  [AW:0]      count
);

  localparam DEPTH = 1 << AW;

  reg [WIDTH-1:0] mem[0:DEPTH-1];
  reg [AW-1:0] wr_ptr;
  reg [AW-1:0] rd_ptr;

  assign full    = (count == DEPTH);
  assign empty   = (count == 0);
  assign rd_data = mem[rd_ptr];

  wire do_wr = wr_en & ~full;
  wire do_rd = rd_en & ~empty;

  always @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= {AW{1'b0}};
      rd_ptr <= {AW{1'b0}};
      count  <= {(AW + 1) {1'b0}};
    end else begin
      if (do_wr) begin
        mem[wr_ptr] <= wr_data;
        wr_ptr      <= wr_ptr + 1'b1;
      end
      if (do_rd) rd_ptr <= rd_ptr + 1'b1;
      case ({do_wr, do_rd})
        2'b10:   count <= count + 1'b1;
        2'b01:   count <= count - 1'b1;
        default: count <= count;
      endcase
    end
  end

endmodule
