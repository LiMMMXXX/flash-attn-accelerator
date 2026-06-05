# FlashAttention 硬件加速器 IP

## 项目简介
基于大模型推理的FlashAttention高性能硬件加速器IP设计。
赛题来源: 集创赛 (Cadence EDA工具链)。
Baseline: S=256, d=64, Q8.8定点, AXI4-Lite+AXI4-Master DMA, Cadence Genus综合。

## 目录结构
- `rtl/` — RTL设计 (SystemVerilog)
- `tb/` — 验证环境 (UVM, 待填充)
- `docs/` — 设计文档
- `model/` — Golden模型 (Python)
- `scripts/` — 仿真/综合脚本

## 当前状态
- [x] 架构设计 (docs/ARCHITECTURE.md)
- [x] RTL骨架文件 (13个模块, rtl/*.sv)
- [x] 开发计划 (docs/DEVELOPMENT_PLAN.md)
- [ ] RTL功能实现
- [ ] UVM验证
- [ ] Genus综合

