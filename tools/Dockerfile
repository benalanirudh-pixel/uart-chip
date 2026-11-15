# Local dev image: iverilog, Verilator, Yosys, cocotb, GTKWave-free (waveforms viewed on host).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      iverilog verilator yosys make g++ python3 python3-venv python3-pip python3-dev \
    && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install --no-cache-dir cocotb==2.0.1 pytest==8.4.2
ENV PATH="/opt/venv/bin:$PATH"
WORKDIR /work
