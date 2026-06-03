# Flash Attention Accelerator

A hardware accelerator library for **Flash Attention** — an I/O-aware exact attention algorithm that dramatically reduces HBM reads/writes by tiling the attention computation and materializing intermediates only in on-chip SRAM.

## Overview

[Flash Attention](https://arxiv.org/abs/2205.14135) reformulates the standard scaled dot‑product attention to exploit the GPU/ASIC memory hierarchy. By dividing Q, K, V into tiles that fit in on‑chip SRAM and applying an **online softmax** with incremental rescaling, it avoids writing the full N×N attention matrix to HBM.

| Metric | Standard Attention | Flash Attention |
|---|---|---|
| HBM accesses | O(N² + Nd) | O(N² / M + Nd) |
| Attention matrix materialized? | Yes (N×N in HBM) | No (tiled in SRAM) |
| Exact result? | Yes | Yes (bitwise identical) |
| Speedup (LLM inference, A100) | 1× | 2–4× |

## Repository Structure

`
flash-attn-accelerator/
├── docs/              # Architecture docs & diagrams
│   └── architecture.html
├── rtl/               # RTL design (Verilog / SystemVerilog)
│   ├── pe/            # Processing elements for matrix multiply
│   ├── sram_ctrl/     # SRAM tile controller
│   ├── softmax/       # Online softmax with rescaling
│   └── top/           # Top-level integration
├── src/               # C / C++ driver & host software
│   ├── runtime/       # Host runtime for accelerator
│   └── tiling/        # Tile scheduler
├── scripts/           # Build & simulation scripts
├── tests/             # Unit tests and verification
├── README.md
└── LICENSE
`

## Key Concepts

### Tiling

The full Q, K, V matrices are split into blocks that each fit in on‑chip SRAM. Computation proceeds tile by tile, keeping intermediate results (partial softmax, partial output) in fast SRAM.

### Online Softmax

Instead of computing the full softmax numerator and denominator across all elements, Flash Attention maintains running statistics (m = max, ℓ = sum of exp) and rescales previous outputs as new tiles arrive:

`
m(x)   ← max(m(x), rowmax(Sⱼ))
ℓ(x)   ← e^(m_old - m_new) · ℓ_old + rowsum(e^(Sⱼ - m_new))
O(x)   ← diag(e^(m_old - m_new)) · O_old + diag(e^(Sⱼ - m_new) / ℓ_new) · Vⱼ
`

### Memory Hierarchy

`
┌──────────────────────────────────────┐
│         HBM  (40–80 GB)              │ ← Q, K, V, O stored here
│   High Bandwidth, High Latency       │
└──────────┬───────────────────────────┘
           │  tile loads & stores
           ▼
┌──────────────────────────────────────┐
│     SRAM  (up to ~20 MB)             │ ← active tiles & intermediates
│   Low Latency, Limited Capacity      │
└──────────────────────────────────────┘
`

## Getting Started

*RTL and software implementation coming soon.*

`ash
# Open the architecture diagram
start docs/architecture.html
`

## References

- [Flash Attention: Fast and Memory-Efficient Exact Attention with IO-Awareness](https://arxiv.org/abs/2205.14135)
- [Flash Attention 2: Faster Attention with Better Parallelism and Work Partitioning](https://arxiv.org/abs/2307.08691)
- [Flash Attention 3: Fast and Accurate Attention with Asynchrony and Low-precision](https://arxiv.org/abs/2407.08614)
