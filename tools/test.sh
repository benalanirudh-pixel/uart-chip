#!/bin/sh
# Run inside the uart-dev container: all cocotb tests, fail if any test failed.
cd test && make clean && make && python -m cocotb_tools.check_results results.xml
