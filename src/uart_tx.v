/*
 * Copyright (c) 2026 anirudh
 * SPDX-License-Identifier: Apache-2.0
 *
 * uart_tx: 8N1 transmitter. Takes bytes from a first-word-fall-through FIFO:
 * when data_valid=1 and idle, it loads data, pulses pop for one clock, and
 * sends start bit, 8 data bits LSB first, stop bit. One bit = 16 ticks.
 * The start bit can be up to one tick short because the tick is free-running.
 */
`default_nettype none

module uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick,        // 16x baud tick
    input  wire       data_valid,  // FIFO not empty
    input  wire [7:0] data,        // FIFO head
    output reg        pop,         // one-clock pulse: byte consumed
    output reg        txd,         // serial line, idle = 1
    output wire       busy
);

  localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

  reg [1:0] state;
  reg [3:0] tcnt;    // ticks inside the current bit
  reg [2:0] bitn;    // index of data bit being sent
  reg [7:0] shreg;

  assign busy = (state != IDLE);

  always @(posedge clk) begin
    pop <= 1'b0;
    if (!rst_n) begin
      state <= IDLE;
      tcnt  <= 4'd0;
      bitn  <= 3'd0;
      shreg <= 8'd0;
      txd   <= 1'b1;
    end else begin
      case (state)
        IDLE: begin
          if (data_valid) begin
            shreg <= data;
            pop   <= 1'b1;
            txd   <= 1'b0;  // start bit
            tcnt  <= 4'd0;
            state <= START;
          end
        end
        default: begin
          if (tick) begin
            tcnt <= tcnt + 4'd1;
            if (tcnt == 4'd15) begin  // end of this bit
              case (state)
                START: begin
                  txd   <= shreg[0];
                  shreg <= {1'b0, shreg[7:1]};
                  bitn  <= 3'd0;
                  state <= DATA;
                end
                DATA: begin
                  if (bitn == 3'd7) begin
                    txd   <= 1'b1;  // stop bit
                    state <= STOP;
                  end else begin
                    txd   <= shreg[0];
                    shreg <= {1'b0, shreg[7:1]};
                    bitn  <= bitn + 3'd1;
                  end
                end
                default: state <= IDLE;  // STOP done
              endcase
            end
          end
        end
      endcase
    end
  end

endmodule
