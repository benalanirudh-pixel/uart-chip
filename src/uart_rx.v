/*
 * Copyright (c) 2026 anirudh
 * SPDX-License-Identifier: Apache-2.0
 *
 * uart_rx: 8N1 receiver with 16x oversampling.
 * - rxd goes through a 2-flop synchronizer.
 * - A falling edge starts a frame; the start bit is re-checked at tick 8
 *   (a glitch is ignored). Then every 16 ticks (mid-bit) a bit is sampled.
 * - After the stop bit, valid pulses for one clock with the byte;
 *   frame_err pulses with it if the stop bit was 0.
 */
`default_nettype none

module uart_rx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick,       // 16x baud tick
    input  wire       rxd,        // asynchronous serial input
    output reg  [7:0] data,
    output reg        valid,      // one-clock pulse: data is new
    output reg        frame_err   // one-clock pulse, same time as valid
);

  localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

  reg [1:0] state;
  reg [3:0] tcnt;
  reg [2:0] bitn;
  reg [7:0] shreg;
  reg       sync1, sync2, sync3;  // sync3 = previous value, for edge detect

  always @(posedge clk) begin
    valid     <= 1'b0;
    frame_err <= 1'b0;
    if (!rst_n) begin
      sync1 <= 1'b1;
      sync2 <= 1'b1;
      sync3 <= 1'b1;
      state <= IDLE;
      tcnt  <= 4'd0;
      bitn  <= 3'd0;
      shreg <= 8'd0;
      data  <= 8'd0;
    end else begin
      sync1 <= rxd;
      sync2 <= sync1;
      sync3 <= sync2;
      case (state)
        IDLE: begin
          if (sync3 && !sync2) begin  // falling edge = start bit
            tcnt  <= 4'd0;
            state <= START;
          end
        end
        START: begin
          if (tick) begin
            if (tcnt == 4'd7) begin
              tcnt <= 4'd0;
              if (sync2) state <= IDLE;  // glitch, not a real start bit
              else begin
                bitn  <= 3'd0;
                state <= DATA;
              end
            end else tcnt <= tcnt + 4'd1;
          end
        end
        DATA: begin
          if (tick) begin
            tcnt <= tcnt + 4'd1;
            if (tcnt == 4'd15) begin  // middle of a data bit
              shreg <= {sync2, shreg[7:1]};  // LSB arrives first
              if (bitn == 3'd7) state <= STOP;
              else bitn <= bitn + 3'd1;
            end
          end
        end
        default: begin  // STOP
          if (tick) begin
            tcnt <= tcnt + 4'd1;
            if (tcnt == 4'd15) begin  // middle of stop bit
              data      <= shreg;
              valid     <= 1'b1;
              frame_err <= ~sync2;
              state     <= IDLE;
            end
          end
        end
      endcase
    end
  end

endmodule
