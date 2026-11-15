#!/bin/bash
# Run inside uart-formal with repo mounted read-only at /work. usage: mutate_formal.sh <1|2|3>
# Breaks a copy of sync_fifo.v; the BMC proof must FAIL.
m=$1
rm -rf /tmp/w; cp -r /work /tmp/w; rm -rf /tmp/w/formal/sync_fifo_*
case $m in
 1) sed -i "s/wire do_wr = wr_en & ~full;/wire do_wr = wr_en;/" /tmp/w/src/sync_fifo.v;;
 2) sed -i "s/assign rd_data = mem\[rd_ptr\];/assign rd_data = mem[rd_ptr + 1'b1];/" /tmp/w/src/sync_fifo.v;;
 3) sed -i "s/wire do_rd = rd_en & ~empty;/wire do_rd = rd_en;/" /tmp/w/src/sync_fifo.v;;
esac
cd /tmp/w/formal && timeout 400 sby -f sync_fifo.sby bmc 2>&1 | grep -E "Assert failed|DONE" | head -3
