# FlashAttention 硬件加速器 — 开发进度跟踪

> **更新规则**: 每完成一个任务，将 `[ ]` 改为 `[x]`，填写完成日期。
> 新会话开始时，Claude 会首先读取此文件了解当前进度。

---

## 📝 用户设计笔记 (自由记录区)

> 这里可以记录任何你认为重要的想法、注意事项、经验教训。
> Claude 每次会话会读取此区域。

### 当前笔记

(暂无，请自由添加)

---

## 🔧 设计决策记录

> 每做一个重要的设计选择，在此记录决策及原因。
> 格式: `[日期] 决策: ... | 原因: ... | 替代方案: ...`

| 日期 | 决策 | 原因 | 替代方案 |
|------|------|------|---------|
| 2026-06-05 | Tile Br=Bc=64 | 平衡复用与SRAM, tile数=16 | Br=32/Bc=128 (面积更大) |
| 2026-06-05 | MAC并行度=64路 | 匹配d=64, 满足<300k cycle | 32路 (cycle翻倍但仍<300k) |
| 2026-06-05 | exp用4次Horner多项式 | 面积小(~300LUT), 精度够 | LUT (面积大, latency 1) |
| 2026-06-05 | exp内部Q8.24精度 | 4次多项式需要24位小数 | Q4.12 (精度不够) |

---

## ❓ 待解决问题

> 记录暂时没有结论、需要后续决定的问题。

- [ ] 待填写

---

## Phase 1: 算法建模

| # | 任务 | 文件 | 状态 | 完成日期 |
|---|------|------|------|---------|
| 1.1 | Python FP32 golden model | `model/golden_model.py` | [ ] | — |
| 1.2 | Q8.8 定点量化模拟 + 误差分析 | `model/golden_model.py` (扩展) | [ ] | — |
| 1.3 | Causal mask 正确性验证 (i=0 corner) | `model/golden_model.py` (test) | [ ] | — |
| 1.4 | Tile 策略验证 (Br=64, Bc=64) | `model/golden_model.py` (tiled) | [ ] | — |
| 1.5 | 性能模型 (理论 cycle + 带宽) | `model/performance_model.py` | [ ] | — |
| 1.6 | 误差预算分析 | `docs/error_budget.md` | [ ] | — |

---

## Phase 2: 核心 RTL 开发

| # | 任务 | 文件 | 状态 | 完成日期 |
|---|------|------|------|---------|
| 2.1 | 定点 exp 5级流水线实现 | `rtl/pipelined_exp_fixed.sv` | [ ] | — |
| 2.2 | exp 单元自检 (随机输入 vs golden) | cocotb 单元测试 | [ ] | — |
| 2.3 | Causal mask 单元实现 | `rtl/causal_mask_unit.sv` | [ ] | — |
| 2.4 | Online softmax FSM (含 exp 实例化) | `rtl/online_softmax_exact.sv` | [ ] | — |
| 2.5 | Online softmax 单元测试 | cocotb 单元测试 | [ ] | — |
| 2.6 | GEMM0 64路并行点积阵列 | `rtl/gemm0_dot_product.sv` | [ ] | — |
| 2.7 | GEMM0 单元测试 | cocotb 单元测试 | [ ] | — |
| 2.8 | Quantize 模块实现 | `rtl/quantize_q8p8.sv` | [ ] | — |
| 2.9 | GEMM1 P×V + rescale | `rtl/gemm1_pv_multiply.sv` | [ ] | — |
| 2.10 | GEMM1 单元测试 | cocotb 单元测试 | [ ] | — |
| 2.11 | 性能计数器 | `rtl/perf_counters.sv` | [ ] | — |
| 2.12 | Tile 预取器 (含 SRAM Buffer) | `rtl/tile_prefetcher.sv` | [ ] | — |

---

## Phase 3: 接口集成

| # | 任务 | 文件 | 状态 | 完成日期 |
|---|------|------|------|---------|
| 3.1 | AXI4-Lite CSR 寄存器文件 | `rtl/axil_csr.sv` | [ ] | — |
| 3.2 | AXI4-Master DMA 引擎 | `rtl/axi4_dma_engine.sv` | [ ] | — |
| 3.3 | 顶层 flashattn_top 集成 + 主FSM | `rtl/flashattn_top.sv` | [ ] | — |
| 3.4 | 端到端集成测试 | cocotb 集成测试 | [ ] | — |

---

## Phase 4: 验证

| # | 任务 | 文件 | 状态 | 完成日期 |
|---|------|------|------|---------|
| 4.1 | AXI4-Lite 寄存器读写测试 | T1 定向测试 | [ ] | — |
| 4.2 | START→BUSY→DONE 流程测试 | T2 定向测试 | [ ] | — |
| 4.3 | SOFT_RESET / IRQ 测试 | T3/T4 定向测试 | [ ] | — |
| 4.4 | 随机 Q/K/V 端到端 (100 seeds) | T5/T6 约束随机 | [ ] | — |
| 4.5 | Causal corner case (i=0/i=255) | T7/T8 定向测试 | [ ] | — |
| 4.6 | 全零/最大值 Edge case | T9/T10 定向测试 | [ ] | — |
| 4.7 | 功能覆盖率 ≥95% | `tb/flashattn_coverage.sv` | [ ] | — |
| 4.8 | 精度验证 (mean<0.03, max<0.10) | Scoreboard | [ ] | — |

---

## Phase 5: Cadence Genus 综合

| # | 任务 | 文件 | 状态 | 完成日期 |
|---|------|------|------|---------|
| 5.1 | SDC 时序约束 | `scripts/flashattn.sdc` | [ ] | — |
| 5.2 | Genus 综合 TCL 脚本 | `scripts/run_synth.tcl` | [ ] | — |
| 5.3 | 初次综合 (baseline) | — | [ ] | — |
| 5.4 | 关键路径分析 + 面积报告 | — | [ ] | — |
| 5.5 | 迭代优化 (流水线/资源共享) | RTL 修改 | [ ] | — |
| 5.6 | 最终综合 (target 频率 + 面积) | — | [ ] | — |

---

## Phase 6: 文档 + 提交

| # | 任务 | 文件 | 状态 | 完成日期 |
|---|------|------|------|---------|
| 6.1 | 完整设计文档 | `docs/DESIGN.md` | [ ] | — |
| 6.2 | 验证报告 | `docs/VERIFICATION.md` | [ ] | — |
| 6.3 | 综合报告 | `docs/SYNTHESIS.md` | [ ] | — |
| 6.4 | 带宽分析 | `docs/BANDWIDTH.md` | [ ] | — |
| 6.5 | 整理提交材料 | — | [ ] | — |

---

## Bonus (可选，独立目录)

| # | 任务 | 目录 | 状态 | 完成日期 |
|---|------|------|------|---------|
| B1 | BF16/FP16 版本 | `bonus/bf16_fp16/` | [ ] | — |
| B2 | 多head支持 (head=4/8) | `bonus/multi_head/` | [ ] | — |
| B3 | 更长序列 (S=512) | `bonus/longer_seq/` | [ ] | — |
| B4 | Padding mask | `bonus/padding_mask/` | [ ] | — |
| B5 | 其他定点格式 (Q6.10/Q4.12) | `bonus/alt_fixed/` | [ ] | — |
| B6 | Dropout (训练模式) | `bonus/dropout/` | [ ] | — |
| B7 | 低精度 INT8/FP8 | `bonus/low_precision/` | [ ] | — |
| B8 | AXI4-Stream 接口 | `bonus/axi_stream/` | [ ] | — |
| B9 | DMA 任务队列 | `bonus/dma_queue/` | [ ] | — |

---

## 快速状态总览

| Phase | 完成/总计 | 进度 |
|-------|----------|------|
| Phase 1: 算法建模 | 0/6 | 0% |
| Phase 2: 核心 RTL | 0/12 | 0% |
| Phase 3: 接口集成 | 0/4 | 0% |
| Phase 4: 验证 | 0/8 | 0% |
| Phase 5: Genus 综合 | 0/6 | 0% |
| Phase 6: 文档+提交 | 0/5 | 0% |
| Bonus | 0/9 | 0% |
