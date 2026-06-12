---
name: flash-attention
description: FlashAttention 硬件加速器 IP 设计与验证。赛题要求：S=256, d=64, Q8.8定点, FlashAttention-style(在线softmax+分块, 禁止显式存储S×S注意力矩阵), AXI4-Lite控制+AXI4-Master DMA数据, Cadence Genus综合。当用户在 flash-attention 目录下工作、编写 RTL(SystemVerilog)、搭建 UVM/cocotb 验证环境、优化 attention 硬件、分析性能或讨论本项目任何模块时，必须使用此 skill。
---

# FlashAttention 硬件加速器 IP — 完整开发指南

> **⚠️ 每次会话第一步：立即读取 `PROGRESS.md` 了解当前开发进度。**
> 该文件记录了每个模块/任务的完成状态。在你开始写任何代码之前，先搞清楚哪些已经做完、哪些还是空白。
> 路径: `D:\17545\Desktop\work\flash-attention\PROGRESS.md`
>
> **工作流程**:
> 1. 读取 `PROGRESS.md` → 了解当前 Phase 和已完成模块
> 2. 读取本 skill 中对应模块的设计要点
> 3. 开发/修改代码
> 4. **完成后更新 `PROGRESS.md`**，将 `[ ]` 改为 `[x]`，填写完成日期

---

## 项目速查卡

| 项目 | 值 |
|------|-----|
| **来源** | 集创赛赛题二 (Cadence EDA 工具链) |
| **GitHub** | https://github.com/LiMMMXXX/flash-attn-accelerator |
| **本地路径** | `D:\17545\Desktop\work\flash-attention` |
| **目标** | 设计一个可综合的 FlashAttention-style 注意力硬件 IP |

---

## 1. 赛题核心约束 (每次写 RTL 前必读)

### 1.1 三类强制算法约束

| 约束 | 要求 | 验收方式 |
|------|------|---------|
| **禁止显式存储 S×S 注意力矩阵** | 不允许在片上实例化 [256,256] 的 score/P 矩阵 | 设计文档 + 代码审查 |
| **必须使用在线(online) softmax** | Milakov-Gimelshein 算法，逐块更新 m/l/O | 功能验证 |
| **必须分块(tiling)处理 K/V** | 外循环遍历 K/V tile，内循环遍历 Q tile | 功能验证 |

### 1.2 Baseline 固定规模

- S = 256 (序列长度)
- d = 64 (Head 维度)
- batch = 1, head = 1
- Q/K/V/O 形状: [256, 64]
- Tile 大小: Br = 64, Bc = 64 (共 4×4 = 16 个 tile)

### 1.3 数据格式 (定点)

| 层级 | 格式 | 位宽 | 说明 |
|------|------|------|------|
| 输入 Q/K/V | Q8.8 有符号定点 | 16-bit | 1b符号 + 7b整数 + 8b小数 |
| Dot-product 累加 | ≥ 32-bit (建议40-bit) | 40-bit | 64个Q8.8×Q8.8不溢出 |
| Softmax exp 内部 | Q8.24 | 32-bit | 精度敏感，24位小数 |
| 统计量 m (max) | Q8.24 | 32-bit | 每行维护 |
| 统计量 l (sum) | Q16.16 | 32-bit | 每行维护，分母累加 |
| O 累加器 | Q16.16 | 32-bit | 中间结果，最终量化截断 |
| 输出 O | Q8.8 有符号定点 | 16-bit | 与输入一致 |

### 1.4 性能目标

| 指标 | 目标值 | 验收方式 |
|------|--------|---------|
| 执行周期数 | < 300k cycles | RTL 仿真计数 |
| 等效逻辑门数 | ≤ 200 万门 | Cadence Genus 报告 |
| 主频 | 越高越好 (≥500MHz) | Genus 时序报告 |
| mean_abs_error | ≤ 0.03 (vs FP32 golden) | Python/cocotb 对比 |
| max_abs_error | ≤ 0.10 (vs FP32 golden) | Python/cocotb 对比 |

### 1.5 接口要求

| 接口 | 类型 | 说明 |
|------|------|------|
| 控制接口 | AXI4-Lite Slave | 主机写寄存器、读状态，地址 8-bit, 数据 32-bit |
| 数据接口 | AXI4-Master + DMA | 加速器主动从内存读 Q/K/V，计算后写回 O |
| 中断 | IRQ_OUT | 完成时触发 |

### 1.6 存储与资源约束 (赛题 §2.1(7) 细则)

- **绝对禁止**: 存储 score/P 全矩阵 (256×256)
- **允许片上缓存**:
  - K tile 块 (≤Bc×d 元素)
  - V tile 块 (≤Bc×d 元素)
  - 每行维护: m (Q8.24), l (Q16.16), O累加 (Q16.16)
  - 必要流水寄存器
- **若全量缓存 K/V 到 SRAM** (非 Baseline 必须，但允许): 必须在报告中量化带宽收益与 SRAM 代价
- **片上 buffer 限额 (不含 Q/K/V/O 完整缓存)**: ~42KB 以内 (见 §6.2)

### 1.7 寄存器映射 (必须实现)

```
0x00 CTRL         R/W  [0]=START(W1自清) [1]=SOFT_RESET [2]=IRQ_EN
0x04 STATUS       R    [0]=BUSY [1]=DONE(W1C) [2]=ERROR
0x08 CFG          R/W  [0]=CAUSAL_EN
0x14 Q_BASE_L     R/W  Q基地址低32位
0x18 Q_BASE_H     R/W  Q基地址高32位
0x1C K_BASE_L     R/W  K基地址低32位
0x20 K_BASE_H     R/W  K基地址高32位
0x24 V_BASE_L     R/W  V基地址低32位
0x28 V_BASE_H     R/W  V基地址高32位
0x2C O_BASE_L     R/W  O基地址低32位
0x30 O_BASE_H     R/W  O基地址高32位
0x34 STRIDE_BYTES R/W  行stride (默认128=d*2)
0x38 NEG_LARGE    R/W  -inf近似值 Q8.8 (默认0x8000)
0x3C SCALE        R/W  1/√d缩放常数 Q8.8 (1/8=0.125=0x0020)
0x40 CYCLES       R    本次执行周期数
```

---

## 2. 算法详解

### 2.1 Scaled Dot-Product Attention (SDPA)

```
score_ij = (Q_i · K_j) / √d + M_ij
P_ij     = exp(score_ij) / Σ_t exp(score_it)
O_i      = Σ_j P_ij · V_j
```

其中 M 是 mask (causal: j > i 时 M_ij = -inf)。

### 2.2 Online Softmax (Milakov-Gimelshein)

对每个新块 B:
```
m_new = max(m_old, max(score_block))
l_new = l_old × exp(m_old - m_new) + Σ exp(score_block - m_new)
O_new = O_old × (l_old / l_new) × exp(m_old - m_new)
      + Σ [exp(score_block - m_new) / l_new] × V_block
```

### 2.3 Tiling 策略

```
外循环 j: 0 → S step Bc=64   (遍历 K/V tile，tile编号 j=0,1,2,3)
  加载 K_tile[64,64], V_tile[64,64] 到 SRAM
  内循环 i: 0 → S step Br=64  (遍历 Q tile，tile编号 i=0,1,2,3)
    加载 Q_tile[64,64] 到 SRAM
    GEMM0: S_ij = Q_tile × K_tile^T → [64, 64]
    对每行: online_softmax(S_ij 的该行) → P_ij
    GEMM1: O_i += P_ij × V_tile → [64, 64]
  写回 O_tile[64,64]
```

K/V tile 在外循环中复用 4 次 (供 4 个 Q tile 计算)，这是核心带宽优化策略。

---

## 3. 模块架构

### 3.1 关键信号命名约定 (子模块互联)

顶层 `flashattn_top` 连接各子模块时，统一使用 `源模块_信号名` 前缀:

```
csr_start        ← axil_csr → top_fsm
dma_rd_req       ← top_fsm → axi4_dma_engine
prefetch_kv_done ← tile_prefetcher → top_fsm
gemm0_score_valid ← gemm0 → softmax
gemm0_score_data  ← gemm0 → softmax
softmax_attn_valid ← softmax → gemm1
softmax_attn_data  ← softmax → gemm1
gemm1_o_valid      ← gemm1 → quantize
quant_o_data       ← quantize → prefetch
stat_m_rd / stat_l_rd  ← stat_RAM ↔ softmax / gemm1
```

### 3.2 文件清单与完成状态

| 文件 | 模块名 | 功能 | 状态 |
|------|--------|------|------|
| `rtl/flashattn_pkg.sv` | flashattn_pkg | 全局参数/类型/函数/常量 | ✅ 完成 |
| `rtl/flashattn_top.sv` | flashattn_top | 顶层 + 主FSM (仅有骨架) | 🔶 骨架 |
| `rtl/axil_csr.sv` | axil_csr | AXI4-Lite 寄存器文件 | 🔶 骨架 |
| `rtl/axi4_dma_engine.sv` | axi4_dma_engine | AXI4-Master DMA引擎 | 🔶 骨架 |
| `rtl/tile_prefetcher.sv` | tile_prefetcher | Tile预取 + SRAM双缓冲 | 🔶 骨架 |
| `rtl/gemm0_dot_product.sv` | gemm0_dot_product | Q×K^T 点积阵列 (64路MAC) | 🔶 骨架 |
| `rtl/causal_mask_unit.sv` | causal_mask_unit | Causal mask 生成 | 🔶 骨架 |
| `rtl/online_softmax_exact.sv` | online_softmax_exact | 在线Softmax FSM (含exp实例化) | 🔶 骨架 |
| `rtl/pipelined_exp_fixed.sv` | pipelined_exp_fixed | ★5级流水线定点exp (最核心) | 🔶 骨架 |
| `rtl/gemm1_pv_multiply.sv` | gemm1_pv_multiply | P×V累加 + rescale | 🔶 骨架 |
| `rtl/quantize_q8p8.sv` | quantize_q8p8 | Q16.16→Q8.8 量化 | 🔶 骨架 |
| `rtl/perf_counters.sv` | perf_counters | 7路性能计数器 | 🔶 骨架 |
| `rtl/block_scale_finder.sv` | block_scale_finder | 块缩放因子 | 🔶 骨架 |

> **图例**: ✅ 完成 | 🔶 骨架 (有接口/注释，缺功能实现) | ⬜ 未开始

### 3.3 模块依赖关系 (开发顺序)

```
flashattn_pkg.sv  ← 无依赖，最先完成 ✅
  ↓
causal_mask_unit.sv  ← 仅依赖 pkg
pipelined_exp_fixed.sv ★  ← 仅依赖 pkg [最关键的模块]
quantize_q8p8.sv  ← 仅依赖 pkg
  ↓
online_softmax_exact.sv  ← 依赖 exp + causal_mask
gemm0_dot_product.sv  ← 依赖 causal_mask (64路并行MAC)
gemm1_pv_multiply.sv  ← 依赖 exp (rescale需要exp)
perf_counters.sv  ← 独立
  ↓
tile_prefetcher.sv  ← 依赖 pkg (SRAM buffer)
axi4_dma_engine.sv  ← 依赖 pkg
axil_csr.sv  ← 依赖 pkg
  ↓
flashattn_top.sv  ← 依赖以上所有模块 (集成 + 主FSM)
```

### 3.4 开发阶段总览

| Phase | 内容 | 状态 |
|-------|------|------|
| Phase 1: 算法建模 | Python golden model + Q8.8量化 + 误差分析 | ⬜ 待开始 |
| Phase 2: 核心 RTL | exp流水线, online softmax, GEMM0/GEMM1 | 🔶 骨架已建 |
| Phase 3: 接口集成 | AXI4-Lite CSR, AXI4-Master DMA, Tile预取器, 顶层 | 🔶 骨架已建 |
| Phase 4: UVM 验证 | cocotb/UVM环境, Golden对比, Corner case | ⬜ 骨架已建 |
| Phase 5: Genus 综合 | SDC约束, 综合脚本, 面积/频率迭代 | ⬜ 待开始 |
| Phase 6: 文档 | 设计/验证/综合报告 | ⬜ 待开始 |
| Bonus (可选) | BF16/多head/长序列/AXI4-Stream等 | ⬜ 独立目录 |

---

## 4. 关键模块设计要点

### 4.1 pipelined_exp_fixed.sv ★ (最重要模块)

- **算法**: 范围缩减 + 4次Horner多项式
- **流水线**: 5级 (范围缩减→r²→Horner1→Horner2→重构)
- **吞吐**: 1 result/cycle, 延迟: 5 cycles
- **输入**: Q8.24, x ≤ 0 (softmax的score-m后总是 ≤ 0)
- **输出**: Q8.24, y ∈ (0, 1]
- **常量**: ln2, 1/ln2, 1, 1/2, 1/6, 1/24 (均Q8.24)
- **下溢保护**: x < -88.7 时输出 0
- **面积**: ~4乘法器 + ~300 LUT
- **精度**: 4次多项式截断误差 < 2⁻²⁰

exp(x), x ≤ 0 算法:
1. 范围缩减: n=floor(x/ln2), r=x-n×ln2, |r|≤ln(2)/2
2. Horner: exp(r) ≈ 1 + r×(1 + r×(1/2 + r×(1/6 + r×1/24)))
3. 重构: exp(x) = exp(r) × 2^n (n≤0, 右移|n|位)

### 4.2 online_softmax_exact.sv

6状态 FSM: IDLE → FIND_ROW_MAX → COMPUTE_EXP → ACCUMULATE_ROW → UPDATE_STATS → DONE

关键数据流:
1. 逐行接收 GEMM0 的 score[0:63]
2. 找行最大值 m_new = max(m_old, row_max)
3. 对每个 score - m_new 送入 exp 流水线
4. 收集 exp 结果 (5 cycle延迟后)
5. 累加 l_new + Σexp
6. 更新 m/l 统计量到 SRAM
7. 将 attn_weight 流式发送到 GEMM1

### 4.3 gemm0_dot_product.sv

- 64路并行MAC: 每cycle计算一整行点积
- Q[row][dim] × K[col][dim] → 40-bit累加
- d=64: 每个点积需64个cycle
- 64×64个点积: 4096 cycle
- 最后 × 1/√d → Q8.8 score
- Causal mask 在 score 输出前叠加

### 4.4 gemm1_pv_multiply.sv

- P=attn_weight [Br,Bc] × V [Bc,d] → O_partial [Br,d]
- 含 rescale: O_new = O_old × fa + P×V (fa = exp(m_old - m_new))
- 需要实例化 exp 单元计算 fa
- 输出 Q16.16 精度的 O_partial

### 4.5 axil_csr.sv

- 两段握手 (地址+数据→响应)
- START 自清除脉冲
- STATUS DONE 写1清除 (W1C)
- 支持 BACKPRESSURE

### 4.6 axi4_dma_engine.sv

- 64-bit AXI4 数据宽度 → 每beat传输4个Q8.8元素
- 1D地址映射: addr = base + (row×stride + col×2)
- 最大 Burst 长度: 16 beats

---

## 5. 验证策略

### 5.1 测试层级

| 层级 | 内容 | 工具 |
|------|------|------|
| 模块级 | exp 单元精度测试 | cocotb + NumPy |
| 模块级 | Online softmax 单行精度测试 | cocotb + NumPy |
| 模块级 | GEMM0/GEMM1 矩阵乘法正确性 | cocotb + NumPy |
| 集成级 | AXI4-Lite 寄存器读写 | UVM/cocotb |
| 集成级 | DMA 读写正确性 | UVM/cocotb |
| 端到端 | 随机 Q/K/V (100 seeds) → 与golden对比 | UVM/cocotb |
| Corner | Causal i=0 只能看 j=0 | 定向测试 |
| Corner | 全零/最大值输入 | 定向测试 |

### 5.2 必测项 (赛题要求)

1. **AXI4-Lite 寄存器读写与启动/完成流程**
2. **随机 Q/K/V 端到端验证** (与 FP32 golden 对比)
3. **Causal mask corner case 验证** (i=0 行只能看 j=0)

### 5.3 Golden Model (Python/NumPy)

```python
def flash_attention_golden(Q, K, V, causal=True):
    """FlashAttention-2 online softmax golden model."""
    S, d = Q.shape
    Br, Bc = 64, 64
    O = np.zeros((S, d), dtype=np.float32)
    l = np.zeros(S, dtype=np.float32)
    m = np.full(S, -np.inf, dtype=np.float32)
    scale = 1.0 / np.sqrt(d)
    for j in range(0, S, Bc):
        Kj, Vj = K[j:j+Bc], V[j:j+Bc]
        for i in range(0, S, Br):
            Qi = Q[i:i+Br]
            S_ij = (Qi @ Kj.T) * scale
            if causal:
                ri = np.arange(i, min(i+Br, S))[:, None]
                rj = np.arange(j, min(j+Bc, S))[None, :]
                S_ij[ri < rj] = -np.inf
            m_old = m[i:i+Br].copy()
            m_new = np.maximum(m_old, S_ij.max(axis=1))
            P = np.exp(S_ij - m_new[:, None])
            l_new = l[i:i+Br] * np.exp(m_old - m_new) + P.sum(axis=1)
            rescale = np.exp(m_old - m_new)
            O[i:i+Br] = O[i:i+Br] * rescale[:, None] + P @ Vj
            m[i:i+Br] = m_new
            l[i:i+Br] = l_new
    return O / l[:, None]
```

### 5.4 cocotb 测试模板 (可直接复制使用)

#### 单个模块测试 — 以 exp 单元为例

```python
# tb/test_exp_unit.py
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
import numpy as np

@cocotb.test()
async def test_exp_precision(dut):
    """验证 exp 单元精度 vs numpy.exp"""
    clock = Clock(dut.clk, 2, units="ns")  # 500MHz
    await cocotb.start(clock)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    errors = []
    for _ in range(10000):
        x_fp = -np.random.rand() * 20.0       # x ∈ [-20, 0]
        x_q8p24 = int(x_fp * (2**24)) & 0xFFFFFFFF
        dut.x_in.value = x_q8p24
        dut.x_valid.value = 1
        await RisingEdge(dut.clk)
        dut.x_valid.value = 0
        # 等 5 级流水线 + 1
        for _ in range(6):
            await RisingEdge(dut.clk)
            if dut.y_valid.value:
                y_q8p24 = dut.y_out.value.signed_integer
                y_fp = y_q8p24 / (2**24)
                expected = np.exp(x_fp)
                rel_err = abs(y_fp - expected) / expected
                errors.append(rel_err)
                break

    max_rel_err = max(errors)
    mean_rel_err = sum(errors) / len(errors)
    cocotb.log.info(f"EXP unit: mean_rel_err={mean_rel_err:.2e}, max_rel_err={max_rel_err:.2e}")
    assert mean_rel_err < 1e-4, f"精度不达标: {mean_rel_err:.2e}"
```

#### 端到端测试模板

```python
# tb/test_e2e_attention.py
@cocotb.test()
async def test_random_attention(dut):
    """随机 Q/K/V 端到端测试 vs golden model"""
    # 1. 产生随机 Q/K/V Q8.8 数据
    np.random.seed(42)
    Q = np.random.randn(256, 64).astype(np.float32) * 0.5
    K = np.random.randn(256, 64).astype(np.float32) * 0.5
    V = np.random.randn(256, 64).astype(np.float32) * 0.5

    # 2. 量化到 Q8.8
    def to_q8p8(arr):
        arr_clipped = np.clip(arr, -128, 127.996)
        return (arr_clipped * 256).astype(np.int16)

    Q_q = to_q8p8(Q); K_q = to_q8p8(K); V_q = to_q8p8(V)

    # 3. 加载到模拟 DDR → 通过 AXI4-Lite 写基地址
    await load_to_ddr(dut, Q_q, base=0x10000)
    await load_to_ddr(dut, K_q, base=0x20000)
    await load_to_ddr(dut, V_q, base=0x30000)

    # 4. 配置寄存器 + 启动
    await write_csr(dut, 0x14, 0x00010000)   # Q_BASE_L
    await write_csr(dut, 0x1C, 0x00020000)   # K_BASE_L
    await write_csr(dut, 0x24, 0x00030000)   # V_BASE_L
    await write_csr(dut, 0x2C, 0x00040000)   # O_BASE_L
    await write_csr(dut, 0x08, 0x1)          # CFG: CAUSAL_EN
    await write_csr(dut, 0x00, 0x1)          # CTRL: START

    # 5. 等待 DONE
    while True:
        status = await read_csr(dut, 0x04)
        if status & 0x2:
            break
        await ClockCycles(dut.clk, 10)

    # 6. 读取 O 输出并反量化
    O_dut_q = await read_from_ddr(dut, base=0x40000, size=256*64)
    O_dut = O_dut_q.astype(np.float32) / 256.0

    # 7. 对比 golden
    O_golden = flash_attention_golden(Q, K, V, causal=True)
    abs_err = np.abs(O_dut - O_golden)
    mean_err = abs_err.mean()
    max_err = abs_err.max()

    cocotb.log.info(f"mean_abs_error={mean_err:.4f}, max_abs_error={max_err:.4f}")
    assert mean_err < 0.03, f"mean_abs_error {mean_err:.4f} >= 0.03"
    assert max_err < 0.10, f"max_abs_error {max_err:.4f} >= 0.10"
```

### 5.5 仿真运行命令

#### cocotb (推荐用于模块级测试)

```bash
# 进入 tb 目录
cd tb

# 测试 exp 单元 (需要先装 cocotb: pip install cocotb)
make test_exp       # SIM=icarus 或 SIM=xcelium

# 测试 online softmax 单元
make test_softmax

# 端到端测试
make test_e2e
```

#### UVM (集成级 / 赛题规定)

```bash
cd tb

# 基础: 寄存器读写 (T1-T4)
make test_basic      # xrun -uvm +UVM_TESTNAME=test_flashattn_basic

# 随机端到端 (T5-T6)
make test_random     # xrun -uvm +UVM_TESTNAME=test_flashattn_random

# 完整回归 (全部 12 项)
make test_complete   # xrun -uvm +UVM_TESTNAME=test_flashattn_complete

# GUI 调试
make xrun_gui
```

> **注意事项**:
> - Makefile 在 `tb/Makefile`，关键变量: `SIM` (仿真器), `UVM_TESTNAME` (测试类名), `SEED` (随机种子)
> - cocotb 需要 Python 环境 + NumPy。第一次运行: `pip install cocotb numpy`
> - 如果用 Cadence Xcelium: `SIM=xcelium make test_exp`
> - 如果用 Icarus Verilog (开源): `SIM=icarus make test_exp`

---

## 6. 性能分析

### 6.1 理论 Cycle 估算 (64路并行MAC)

| 操作 | Cycles/每tile | 说明 |
|------|--------------|------|
| GEMM0: Q×K^T | 4,096 | 64×64×64 MAC / 64并行 |
| Softmax: exp | 4,096 + 64 | per-row overhead |
| GEMM1: P×V | 4,096 | 同 GEMM0 |
| DMA: 加载 K/V | ~1,024 | 复用 (外循环) |
| DMA: 加载 Q | ~512 | (内循环) |
| DMA: 写回 O | ~512 | (内循环) |
| **每tile 合计** | ~14,000 | 含流水线重叠 |
| **16 tiles 总计** | ~224,000 | < 300k ✓ |

### 6.2 存储需求

| Buffer | 尺寸 | 容量 |
|--------|------|------|
| K Tile Buffer | 64×64×16bit | 8 KB |
| V Tile Buffer | 64×64×16bit | 8 KB |
| Q Tile Buffer | 64×64×16bit | 8 KB |
| m/l Statistics | 256×2×32bit | 2 KB |
| O Accumulator | 64×64×32bit | 16 KB |
| Score 行缓冲 | 64×16bit | 128 B |
| **总计** | | **~42 KB** |

**关键**: 不存储 S×S (256KB) 全注意力矩阵，仅 ~42KB，满足赛题约束。

---

## 7. 开发工作流 (Git)

### 7.1 分支规范

```
main                    主分支，永远稳定
feat/<功能名>           新功能
fix/<问题名>            修 bug
hw/<模块名>             硬件 RTL
doc/<文档名>            文档
test/<测试名>           测试
```

### 7.2 提交规范

```
<type>: <short summary>
  - <detail 1>
  - <detail 2>

类型: feat, fix, hw, doc, refac, test, wip
```

### 7.3 开发流程

1. `git switch main && git pull --rebase`
2. `git switch -c hw/<module-name>`
3. 开发 + 小步提交
4. `git push -u origin hw/<module-name>`
5. 开 PR → Review → Merge
6. 删除分支

---

## 8. 编码规范 (SystemVerilog)

### 8.1 文件结构顺序

1. 模块声明 + 参数
2. 端口声明 (时钟复位 → 控制 → 数据输入 → 数据输出)
3. localparam
4. typedef enum
5. 信号声明
6. 子模块实例化
7. always_comb (组合逻辑, 阻塞赋值 =)
8. always_ff (时序逻辑, 非阻塞赋值 <=)
9. assign (连续赋值)
10. 断言 (`ifdef SIMULATION`)

### 8.2 命名规范

| 对象 | 规范 | 示例 |
|------|------|------|
| 模块名 | snake_case | `pipelined_exp_fixed` |
| 参数 | UPPER_SNAKE | `TILE_BR`, `DATA_WIDTH` |
| 信号 | snake_case + 语义后缀 | `score_valid`, `gemm0_busy` |
| FSM 状态 | UPPER_SNAKE | `SM_IDLE`, `MAIN_LOAD_KV` |
| 常量 | C_ + UPPER_SNAKE | `C_LN2`, `C_INV_LN2` |
| 寄存器 | `_q` 后缀 | `state_q`, `counter_q` |
| 低有效 | `_n` 后缀 | `rst_n` |

### 8.3 必须遵守的规则

- 每个 `case` 必须有 `default`
- 所有寄存器在 reset 赋已知值 (禁止 X 传播)
- 模块输出打一拍 reg
- 参数化所有位宽和深度
- 禁止 `full_case` / `parallel_case`
- 使用 `flashattn_pkg` 中的类型和常量

### 8.4 SVA 断言 (推荐添加于每个模块)

```systemverilog
// FSM 合法性检查 (放在 flashattn_top)
`ifdef SIMULATION
property p_fsm_legal;
    @(posedge clk) disable iff (!rst_n)
    state_q inside {
        MAIN_IDLE, MAIN_INIT_STATS, MAIN_LOAD_KV, MAIN_LOAD_Q,
        MAIN_GEMM0, MAIN_SOFTMAX, MAIN_GEMM1, MAIN_NEXT_Q,
        MAIN_NEXT_KV, MAIN_WRITEBACK, MAIN_DONE
    };
endproperty
a_fsm_legal: assert property(p_fsm_legal) else $error("FSM illegal state");

// AXI4-Lite 握手不丢失 (放在 axil_csr)
property p_axil_wr_handshake;
    @(posedge clk) disable iff (!rst_n)
    s_axil_awvalid && s_axil_awready
    |=> s_axil_wvalid && s_axil_wready
    ##[0:5] s_axil_bvalid;
endproperty
a_axil_wr: assert property(p_axil_wr_handshake);

// GEMM0 没有 stall 超过 100 cycle (性能检测)
property p_no_long_stall;
    @(posedge clk) disable iff (!rst_n)
    gemm0_busy |-> ##[0:100] gemm0_done;
endproperty
a_no_stall: assert property(p_no_long_stall);
`endif
```

---

## 9. 常见陷阱与注意事项

1. **Q8.8 溢出**: 64次乘积累加需 ≥40-bit 累加器，32-bit 不够
2. **exp 下溢**: x < -88.7 时 exp→0，需下溢保护 (输出直接置 0)
3. **Causal mask 时序**: mask 必须在 GEMM0 同时应用 (不是后处理)
4. **l 精度**: 分母累加使用 Q16.16+，精度不够会导致 softmax 归一化错误
5. **m rescale**: m 更新时 O 的 rescale 影响最终精度，注意乘法器精度
6. **AXI4 握手**: VALID/READY 必须正确处理 BACKPRESSURE
7. **Genus SRAM 推断**: 二维 reg 数组可能推断为寄存器而非 BRAM
8. **exp 流水线气泡**: 5 级延迟在启动时有气泡，但稳态吞吐 = 1/cycle
9. **FP32→Q8.8**: 不能直接照搬 FP32 的参考设计，定点 exp 完全不同
10. **Bonus 必须独立**: Bonus 代码必须放独立目录，不修改 Baseline

---

## 10. 文件导航

完整的设计文档路径列表：

| 路径 | 内容 |
|------|------|
| `题目要求.md` | 赛题原始要求 (最权威) |
| `PROGRESS.md` | **开发进度追踪 + 设计笔记 + 待解决问题** (每次必读) |
| `docs/ARCHITECTURE.md` | 详细架构设计 (模块接口、FSM、精度分析) |
| `docs/DEVELOPMENT_PLAN.md` | 6阶段开发计划 (任务分解、工时估算) |
| `docs/UVM_GUIDE.md` | UVM 验证方法论指南 (从零学习) |
| `docs/development-workflow.md` | Git 开发流程 |
| `flashattn_skill.md` | 旧版技能文档 (本文档已替代) |

### 赛题提交清单 (参照题目要求 §四)

| # | 类别 | 必须交付 |
|---|------|---------|
| 1 | RTL 代码 | `rtl/` 下全部 SystemVerilog 源文件 |
| 2 | Cadence 脚本 | `scripts/run_synth.tcl`, `scripts/flashattn.sdc` |
| 3 | 验证代码 | `tb/` UVM 环境 + cocotb 测试 + 测试向量 |
| 4 | Genus 报告 | 仿真报告、波形文件、物理综合报告 (面积/时序/功耗) |
| 5 | 设计文档 | 架构设计、验证报告、综合报告、带宽分析 |

---

## 11. 当前会话工作指南

### 每次会话开始时 (必须)

1. **读取 `PROGRESS.md`** → 了解各模块完成状态（这是唯一的真实状态来源）
2. **读取 `git status` / `git log --oneline -5`** → 确认当前分支和最近提交
3. **确定当前 Phase 和下一个要做的任务** → 从未完成的 Phase 最早任务开始

### 开发一个模块时

1. 从 `PROGRESS.md` 找到下一个 `[ ]` 任务
2. 在本 skill 中找到对应模块的设计要点 (§4)
3. 读一下依赖模块的代码（确保接口匹配）
4. 实现功能
5. 完成后：
   - **更新 `PROGRESS.md`** — 将 `[ ]` 改为 `[x]`，填日期
   - git commit (遵循 `hw: <描述>` 规范)

### 验证一个模块时

1. 写 cocotb 或 UVM 测试
2. 运行仿真
3. 对比 golden model
4. **更新 `PROGRESS.md`** 对应的测试任务

### 禁止行为

- ❌ 不读 `PROGRESS.md` 就开始写代码
- ❌ 完成了模块但不更新 `PROGRESS.md`
- ❌ 只看 skill 里的静态状态 (那可能已过时)，不看 PROGRESS.md 的真实状态

---

## 12. 用户补充说明接口

`PROGRESS.md` 为你预留了三个自由编辑区，Claude 每次会话会自动读取：

| 区域 | 位置 | 用途 |
|------|------|------|
| 📝 **用户设计笔记** | PROGRESS.md 顶部 | 记录任何想法、经验教训、注意事项 |
| 🔧 **设计决策记录** | PROGRESS.md 顶部 (表格) | 记录每个关键决策及原因 |
| ❓ **待解决问题** | PROGRESS.md 顶部 (checklist) | 记录暂时没有结论的问题 |

**使用方式**:
- 你可以直接在 IDE 中打开 `PROGRESS.md` 编辑这些区域
- 也可以对我说 "把这个记到笔记里" 或 "这个决策记录下来"，我会帮你更新 PROGRESS.md

**建议记录的内容**:
- 你发现的 tricky 问题及解法 (下次不用再排)
- 你不确定的接口设计选择 (留待后续验证)
- 综合/仿真时遇到的 Cadence 工具特殊行为
- 对某个 Bonus 的实现思路 (即使现在不做)

---

> **注意**: 本 skill 中 §3.2 的"状态"列是项目初始时的快照，**可能已过时**。
> 唯一真实的状态来源是 `PROGRESS.md`。如果两者不一致，以 `PROGRESS.md` 为准。
