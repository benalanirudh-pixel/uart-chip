/*
 * Copyright (c) 2026 anirudh
 * SPDX-License-Identifier: Apache-2.0
 *
 * UART controller top level. See docs/spec.md for the pin map, registers and
 * bus protocol.
 */
`default_nettype none

module tt_um_anirudh_uart (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // ---------------------------------------------------------------- host bus input sync
  // {data[7:0], addr[1:0], rd, wr}: all bits get the same 2-flop delay.
  reg [11:0] hs1, hs2;
  reg       wr_d, rd_d;  // previous strobe values, for rising-edge detect

  always @(posedge clk) begin
    if (!rst_n) begin
      hs1  <= 12'd0;
      hs2  <= 12'd0;
      wr_d <= 1'b0;
      rd_d <= 1'b0;
    end else begin
      hs1  <= {uio_in, ui_in[5:4], ui_in[1:0]};
      hs2  <= hs1;
      wr_d <= hs2[0];
      rd_d <= hs2[1];
    end
  end

  wire       wr_s   = hs2[0];
  wire       rd_s   = hs2[1];
  wire [1:0] addr_s = hs2[3:2];
  wire [7:0] d_s    = hs2[11:4];

  wire wr_edge = wr_s & ~wr_d & ~rd_s;  // RD wins if both are high
  wire rd_edge = rd_s & ~rd_d;

  // ---------------------------------------------------------------- registers & flags
  reg [15:0] div;
  reg        tx_rej, frame_err_f, overrun_f;  // sticky flags
  reg  [7:0] rdata;

  wire tx_full, tx_empty, rx_full, rx_empty;
  wire [7:0] tx_head, rx_head;
  wire [3:0] tx_count_unused, rx_count_unused;

  wire tx_push = wr_edge & (addr_s == 2'd0);
  wire rx_pop  = rd_edge & (addr_s == 2'd0);
  wire w_stat  = wr_edge & (addr_s == 2'd1);

  wire       rx_valid, rx_ferr;
  wire [7:0] rx_data;
  wire       tx_pop, tx_busy;
  wire       tick;
  wire       txd;

  wire tx_idle = tx_empty & ~tx_busy;

  wire [7:0] status = {overrun_f, frame_err_f, tx_rej, tx_idle, rx_full, tx_busy | ~tx_empty,
                       ~tx_full, ~rx_empty};

  always @(posedge clk) begin
    if (!rst_n) begin
      div         <= 16'd27;  // 50 MHz / (16 * 115200) = 27.1
      tx_rej      <= 1'b0;
      frame_err_f <= 1'b0;
      overrun_f   <= 1'b0;
      rdata       <= 8'd0;
    end else begin
      // write-1-to-clear first, then set events win
      if (w_stat) begin
        if (d_s[5]) tx_rej      <= 1'b0;
        if (d_s[6]) frame_err_f <= 1'b0;
        if (d_s[7]) overrun_f   <= 1'b0;
      end
      if (tx_push & tx_full)  tx_rej      <= 1'b1;
      if (rx_ferr)            frame_err_f <= 1'b1;
      if (rx_valid & rx_full) overrun_f   <= 1'b1;

      if (wr_edge && addr_s == 2'd2) div[7:0]  <= d_s;
      if (wr_edge && addr_s == 2'd3) div[15:8] <= d_s;

      if (rd_edge) begin
        case (addr_s)
          2'd0:    rdata <= rx_empty ? 8'd0 : rx_head;
          2'd1:    rdata <= status;
          2'd2:    rdata <= div[7:0];
          default: rdata <= div[15:8];
        endcase
      end
    end
  end

  // ---------------------------------------------------------------- blocks
  baud_gen u_baud (
      .clk  (clk),
      .rst_n(rst_n),
      .div  (div),
      .tick (tick)
  );

  sync_fifo #(.WIDTH(8), .AW(3)) u_tx_fifo (
      .clk    (clk),
      .rst_n  (rst_n),
      .wr_en  (tx_push),
      .wr_data(d_s),
      .rd_en  (tx_pop),
      .rd_data(tx_head),
      .full   (tx_full),
      .empty  (tx_empty),
      .count  (tx_count_unused)
  );

  uart_tx u_tx (
      .clk       (clk),
      .rst_n     (rst_n),
      .tick      (tick),
      .data_valid(~tx_empty),
      .data      (tx_head),
      .pop       (tx_pop),
      .txd       (txd),
      .busy      (tx_busy)
  );

  uart_rx u_rx (
      .clk      (clk),
      .rst_n    (rst_n),
      .tick     (tick),
      .rxd      (ui_in[3]),
      .data     (rx_data),
      .valid    (rx_valid),
      .frame_err(rx_ferr)
  );

  sync_fifo #(.WIDTH(8), .AW(3)) u_rx_fifo (
      .clk    (clk),
      .rst_n  (rst_n),
      .wr_en  (rx_valid),
      .wr_data(rx_data),
      .rd_en  (rx_pop),
      .rd_data(rx_head),
      .full   (rx_full),
      .empty  (rx_empty),
      .count  (rx_count_unused)
  );

  // ---------------------------------------------------------------- outputs
  assign uo_out = {1'b0, rx_full, tx_busy | ~tx_empty, txd, frame_err_f, overrun_f, ~tx_full, ~rx_empty};
  assign uio_out = rdata;
  assign uio_oe = {8{rd_s}};

  // ena and unused input pins
  wire _unused = &{ena, ui_in[7:6], ui_in[2], tx_count_unused, rx_count_unused, 1'b0};

endmodule
