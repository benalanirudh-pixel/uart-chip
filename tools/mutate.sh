#!/bin/bash
# Mutation check, run inside uart-dev with the repo mounted read-only at /work.
# usage: mutate.sh <1|2|3>   - breaks a copy of the RTL; tests must FAIL.
m=$1
rm -rf /tmp/w; cp -r /work /tmp/w; rm -rf /tmp/w/test/sim_build /tmp/w/test/results.xml
case $m in
 1) sed -i "s/{sync2, shreg\[7:1\]}/{shreg[6:0], sync2}/" /tmp/w/src/uart_rx.v;;
 2) sed -i "s/count == DEPTH)/count == DEPTH-1)/" /tmp/w/src/sync_fifo.v;;
 3) sed -i "s/frame_err <= ~sync2;/frame_err <= 1'b0;/" /tmp/w/src/uart_rx.v;;
esac
cd /tmp/w/test && timeout 150 make 2>&1 | grep -E "TESTS=|FAIL  " | head -8
python -m cocotb_tools.check_results results.xml >/dev/null 2>&1; echo "check_results exit=$?"
