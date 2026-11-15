/*
 * Copyright (c) 2026 anirudh
 * SPDX-License-Identifier: Apache-2.0
 *
 * baud_gen: emits a one-clock-wide "tick" every DIV clocks (16x baud rate).
 * DIV = 0 is treated as 1.
 */
`default_nettype none

module baud_gen (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] div,
    output reg         tick
);

  reg [15:0] cnt;  // counts 1..div
  wire [15:0] top = (div == 16'd0) ? 16'd1 : div;

  always @(posedge clk) begin
    if (!rst_n) begin
      cnt  <= 16'd1;
      tick <= 1'b0;
    end else if (cnt >= top) begin  // ">=" so a smaller DIV written mid-count still works
      cnt  <= 16'd1;
      tick <= 1'b1;
    end else begin
      cnt  <= cnt + 16'd1;
      tick <= 1'b0;
    end
  end

endmodule
