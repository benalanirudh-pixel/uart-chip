#!/bin/sh
# Run inside the uart-dev container: verilator lint, all warnings on.
verilator --lint-only -Wall --top-module tt_um_anirudh_uart src/*.v && echo LINT_OK
