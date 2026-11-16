#!/usr/bin/env python3
"""Draw docs/waveform.png (one TX frame of 0x55) from test/tb.vcd.

Make the VCD:  fst2vcd test/tb.fst -o test/tb.vcd   (inside the uart-formal image)
Plot:          python tools/plot_wave.py test/tb.vcd docs/waveform.png   (needs matplotlib)
"""
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

T0, T1 = 1_720_000, 15_500_000  # ps window = test_2_send_one_byte (cocotb timescale 1 ps)


def parse(path):
    ids, scope, changes, t = {}, [], {}, 0
    for line in open(path):
        p = line.split()
        if not p:
            continue
        if p[0] == "$scope":
            scope.append(p[2])
        elif p[0] == "$upscope":
            scope.pop()
        elif p[0] == "$var" and scope == ["tb"]:
            ids.setdefault(p[3], (p[4], int(p[2])))
        elif p[0].startswith("#"):
            t = int(p[0][1:])
        elif p[0][0] in "01xz" and len(p) == 1 and p[0][1:] in ids:
            changes.setdefault(p[0][1:], []).append((t, p[0][0]))
        elif p[0][0] == "b" and len(p) == 2 and p[1] in ids:
            changes.setdefault(p[1], []).append((t, p[0][1:]))
    return ids, changes


def series(ids, changes, name, bit=None):
    sid = next(i for i, (n, _) in ids.items() if n == name)
    pts = []
    for t, v in changes.get(sid, []):
        if bit is None:
            pts.append((t, v))
        else:
            v = v.rjust(ids[sid][1], "0")
            pts.append((t, v[::-1][bit] if v[::-1][bit] in "01" else "0"))
    return pts


def at(pts, t):
    cur = pts[0][1]
    for tt, v in pts:
        if tt > t:
            break
        cur = v
    return cur


def main(vcd, out):
    ids, ch = parse(vcd)
    ts = [T0 + i * 20_000 for i in range((T1 - T0) // 20_000)]  # every 20 ns clock
    sig = [
        ("WR strobe  (ui_in[0])", series(ids, ch, "ui_in", 0)),
        ("TX_READY   (uo_out[1])", series(ids, ch, "uo_out", 1)),
        ("TXD        (uo_out[4])", series(ids, ch, "uo_out", 4)),
        ("TX_BUSY    (uo_out[5])", series(ids, ch, "uo_out", 5)),
    ]
    fig, axs = plt.subplots(len(sig), 1, figsize=(11, 4.2), sharex=True)
    for ax, (label, pts) in zip(axs, sig):
        ax.step([t / 1000 for t in ts], [int(at(pts, t)) for t in ts], where="post", lw=1.4)
        ax.set_ylim(-0.2, 1.3)
        ax.set_yticks([0, 1])
        ax.set_ylabel(label, rotation=0, ha="right", va="center", fontsize=8)
    axs[-1].set_xlabel("time (ns)    DIV = 4, 50 MHz clock, WR pulses 1-2 set DIV, pulse 3 writes 0x55")
    axs[2].set_title("TXD: start bit, 0x55 sent LSB first (alternating 1,0,...), stop bit", fontsize=9)
    fig.tight_layout()
    fig.savefig(out, dpi=110)


main(sys.argv[1], sys.argv[2])
