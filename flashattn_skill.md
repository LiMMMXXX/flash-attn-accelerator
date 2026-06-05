---
name: flashattn-accelerator-ip
description: Design and verify FlashAttention hardware accelerator IP in SystemVerilog — online softmax, tiling, Q8.8 fixed-point datapath, AXI4-Lite/AXI4-Master interfaces, Cadence Genus synthesis targeting. Use for writing RTL, building UVM/cocotb testbenches, optimizing attention hardware, or analyzing performance of FlashAttention-style accelerators.
---

# FlashAttention 高性能硬件加速器 IP 设计

## 技能概述

本技能为"基于大模型推理的FlashAttention 高性能硬件加速器 IP 设计"赛题提供专用的 SystemVerilog 设计与验证能力。涵盖在线 softmax 算法、分块（tiling）数据流、Q8.8 定点数据通路、AXI4-Lite 控制接口、AXI4-Master DMA 数据接口、Cadence Genus 综合优化以及 UVM/cocotb 验证方法论。

## 适用场景

使用本技能当用户需要：
- 编写 FlashAttention 硬件加速器的 RTL 设计
- 实现在线 softmax 和分块注意力算法
- 设计 Q8.8/Q8.24 等定点数据通路
- 构建 AXI4-Lite 控制和 AXI4-Master DMA 数据接口
- 搭建 UVM 或 cocotb 验证环境
- 优化 Cadence Genus 综合的面积/频率
- 分析性能（cycles、带宽利用率、资源开销）
- 评审或调试 FlashAttention 相关硬件代码

---

## 1. 赛题核心约束速查

在编写任何 RTL 之前，必须先确认以下约束：

### 1.1 算法约束

| 约束 | 要求 |
|------|------|
| 禁止显式存储 S×S 注意力矩阵 | 必须使用在线 softmax + 分块 |
| 必须使用在线（online）softmax | Milakov-Gimelshein 算法 |
| 必须分块处理 K/V | 外循环遍历 K/V tile，内循环遍历 Q tile |

### 1.2 Baseline 固定规模

| 参数 | 值 |
|------|-----|
| 序列长度 S | 256 |
| Head 维度 d | 64 |
| Batch | 1 |
| Head 数量 | 1 |
| Q/K/V/O 形状 | [256, 64] |

### 1.3 数据格式（定点）

| 层级 | 格式 | 说明 |
|------|------|------|
| 输入 Q/K/V | Q8.8（16-bit 有符号） | 1 位符号 + 7 位整数 + 8 位小数 |
| Dot-product 累加 | ≥ 32-bit（建议 40-bit） | 防止溢出 |
| Softmax 中间 | 允许更高位宽或分段缩放 | exp 路径精度敏感 |
| 输出 O | Q8.8（16-bit 有符号） | 与输入一致 |

### 1.4 性能目标

| 指标 | 目标 |
|------|------|
| 执行周期数 | < 300k cycles（S=256, d=64, causal）|
| 等效逻辑门数 | ≤ 200 万门（含存储器折算，2-input NAND 等效） |
| 主频 | 越高越好（Cadence Genus 综合） |
| 带宽 | 给出 RD_BYTES / WR_BYTES 分析 |

### 1.5 正确性验收

| 指标 | 门限 |
|------|------|
| mean_abs_error | ≤ 0.03（vs FP32 golden） |
| max_abs_error | ≤ 0.10（vs FP32 golden） |
| 测试覆盖 | AXI4-Lite 读写 + 随机端到端 + Causal mask corner case |

---

## 2. 算法基础

### 2.1 Scaled Dot-Product Attention (SDPA)

```
score_{ij} = (Q_i · K_j) / √d + M_{ij}
P_{ij}     = exp(score_{ij}) / Σ_t exp(score_{it})
O_i        = Σ_j P_{ij} · V_j
```

### 2.2 Online Softmax（Milakov-Gimelshein 算法）

```
对于每个新块 B：
  m_new = max(m_old, max(score_block))
  l_new = l_old × exp(m_old - m_new) + Σ exp(score_block - m_new)
  O_new = O_old × (l_old / l_new) × exp(m_old - m_new)
        + Σ [exp(score_block - m_new) / l_new] × V_block
```

### 2.3 Tiling 策略

```
外循环 j: 0 → S step Bc   (遍历 K/V tile)
  内循环 i: 0 → S step Br  (遍历 Q tile)
    加载 K_tile[Bc, d], V_tile[Bc, d]
    对每个 Q_tile[Br, d]:
      S_ij = Q_tile × K_tile^T        // GEMM0, 结果: [Br, Bc]
      P_ij = online_softmax(S_ij)      // 在线 softmax
      O_i += P_ij × V_tile            // GEMM1, 累加到输出: [Br, d]
  写回 O_tile[Br, d]
```

Baseline 推荐 tile 大小：Br = Bc = 64。

---

## 3. 定点数据路径设计

### 3.1 Q8.8 格式规范

```
位布局: [15] = 符号位, [14:8] = 整数部分, [7:0] = 小数部分
范围: [-128.996, +127.996]
精度: 1/256 ≈ 0.0039
```

### 3.2 Q8.8 算术规则

```systemverilog
// Q8.8 类型定义
typedef logic signed [15:0] q8p8_t;

// 乘法：Q8.8 × Q8.8 → Q16.16
function automatic logic signed [31:0] mul_q8p8_full(
    input q8p8_t a, input q8p8_t b
);
    mul_q8p8_full = $signed(a) * $signed(b);
endfunction

// 加法/累加：Q8.8 + Q8.8 → 注意饱和
```

### 3.3 扩展精度定点

| 操作 | 输入格式 | 建议中间格式 | 输出格式 |
|------|---------|-------------|---------|
| Dot-product 累加 | Q8.8 × Q8.8 | Q16.16 累加器 | Q8.8 |
| Softmax max 计算 | Q8.8 | Q8.8 | Q8.8 |
| exp(x) 输入 | Q8.8（x ≤ 0） | Q8.24（内部） | Q8.24 |
| l 累加（分母） | Q8.24 | Q16.16 | Q8.24 |
| O 累加（分子） | Q8.24 × Q8.8 | Q16.16 | Q8.8 |
| 1/√d 缩放 | Q8.8 | Q8.24 | Q8.8 |

---

## 4. 模块架构

### 4.1 推荐文件结构

```
flashattn_accelerator/
├── rtl/
│   ├── flashattn_pkg.sv              # 全局包：类型定义、参数、函数
│   ├── flashattn_top.sv              # 顶层：CSR、FSM、子模块互联
│   ├── axil_csr.sv                   # AXI4-Lite 寄存器读写
│   ├── axi4_dma_engine.sv            # AXI4-Master DMA 读取/写回
│   ├── tile_prefetcher.sv            # Tile 预取 + 双缓冲
│   ├── gemm0_dot_product.sv          # GEMM0: Q × K^T 点积阵列
│   ├── online_softmax_exact.sv       # 在线 softmax（Milakov-Gimelshein）
│   ├── pipelined_exp_fixed.sv        # 定点流水线 exp(x) 单元 ★核心
│   ├── gemm1_pv_multiply.sv          # GEMM1: P × V 累加
│   ├── causal_mask_unit.sv           # Causal mask 生成
│   ├── quantize_q8p8.sv              # Q16.16 → Q8.8 量化
│   ├── perf_counters.sv              # 性能计数器
│   └── block_scale_finder.sv         # 块缩放因子
├── tb/
│   ├── env/                          # UVM/cocotb Agent/Driver/Monitor
│   ├── seq/                          # 测试序列
│   ├── scoreboard.sv                 # 计分板
│   ├── coverage.sv                   # 功能覆盖率
│   └── test_top.sv                   # 测试顶层
├── model/
│   └── golden_model.py               # Python FP32 golden 模型
├── scripts/
│   ├── run_sim.tcl                   # Xcelium 仿真脚本
│   ├── run_synth.tcl                 # Genus 综合脚本
│   └── run_formal.tcl                # 形式验证（可选）
└── README.md
```

---

## 5. 关键模块设计模板

### 5.1 pipelined_exp_fixed.sv — 定点流水线 exp 单元 ★

这是整个加速器最关键的数据通路模块。

**算法**：范围缩减 + 4 次多项式（Horner 方法），5 级流水线，1 result/cycle。

```
exp(x), x ≤ 0:
1. 范围缩减: x = n × ln(2) + r, n = floor(x / ln(2)), |r| ≤ ln(2)/2
2. Horner: exp(r) ≈ 1 + r × (1 + r × (1/2 + r × (1/6 + r × 1/24)))
3. 重构: exp(x) = exp(r) × 2^n (n ≤ 0, 右移 |n| 位)
```

**Q8.24 常量表**：
| 常量 | 值 (Q8.24 hex) | 说明 |
|------|----------------|------|
| ln(2) | 0x00B17218 | ~0.693147 |
| 1/ln(2) | 0x01715476 | ~1.442695 |
| 1 | 0x01000000 | 1.0 |
| 1/2 | 0x00800000 | 0.5 |
| 1/6 | 0x002AAAAB | ~0.166667 |
| 1/24 | 0x000AAAAB | ~0.041667 |

```systemverilog
// ==========================================================================
// pipelined_exp_fixed — 5 级流水线定点 exp(x) 单元
// ==========================================================================
// 输入:  Q8.24 定点有符号，x ≤ 0（softmax 输入经 max 减法后总是 ≤ 0）
// 输出:  Q8.24 定点有符号，exp(x) ∈ (0, 1]
// 吞吐:  1 element/cycle, 延迟: 5 cycles
// 面积:  ~4 个乘法器，~300 LUT
// ==========================================================================

`timescale 1ns / 1ps

module pipelined_exp_fixed #(
    parameter int DATA_WIDTH = 32
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic signed [DATA_WIDTH-1:0] x_in,
    input  logic                         x_valid,
    output logic signed [DATA_WIDTH-1:0] y_out,
    output logic                         y_valid
);

    localparam signed [31:0] C_LN2     = 32'sh00B17218;
    localparam signed [31:0] C_INV_LN2 = 32'sh01715476;
    localparam signed [31:0] C_ONE     = 32'sh01000000;
    localparam signed [31:0] C_HALF    = 32'sh00800000;
    localparam signed [31:0] C_INV6    = 32'sh002AAAAB;
    localparam signed [31:0] C_INV24   = 32'sh000AAAAB;

    // Stage 1-4 pipeline registers
    logic signed [31:0] s1_n, s1_r, s2_r, s2_r2, s2_n;
    logic signed [31:0] s3_p, s3_r, s3_r2, s3_n;
    logic signed [31:0] s4_exp_r, s4_n;
    logic               s1_valid, s2_valid, s3_valid, s4_valid;
    logic               s1_underflow, s2_underflow, s3_underflow, s4_underflow;

    // ======================================================================
    // Stage 1: 范围缩减 n = floor(x / ln(2)), r = x - n×ln(2)
    // ======================================================================
    logic signed [63:0] s1_prod_c, s1_nln2_c;
    logic signed [31:0] s1_n_tmp_c, s1_r_c;
    logic               s1_uf_c;

    always_comb begin
        s1_prod_c  = x_in * C_INV_LN2;
        s1_n_tmp_c = s1_prod_c[55:24];
        s1_nln2_c  = s1_n_tmp_c * C_LN2;
        s1_r_c     = x_in - s1_nln2_c[55:24];
        s1_uf_c    = (x_in < -32'sh574CCCCD);  // x < -88.7
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0; s1_n <= 0; s1_r <= 0; s1_underflow <= 0;
        end else begin
            s1_valid <= x_valid; s1_n <= s1_n_tmp_c;
            s1_r <= s1_r_c; s1_underflow <= s1_uf_c;
        end
    end

    // ======================================================================
    // Stage 2: r² 计算
    // ======================================================================
    logic signed [63:0] s2_sq_c;
    always_comb s2_sq_c = s1_r * s1_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 0; s2_r <= 0; s2_r2 <= 0; s2_n <= 0; s2_underflow <= 0;
        end else begin
            s2_valid <= s1_valid; s2_r <= s1_r;
            s2_r2 <= s2_sq_c[55:24]; s2_n <= s1_n;
            s2_underflow <= s1_underflow;
        end
    end

    // ======================================================================
    // Stage 3: Horner 第一步 p = 1/2 + r × (1/6 + r/24)
    // ======================================================================
    logic signed [63:0] s3_t1_c, s3_t2_c;
    logic signed [31:0] s3_inner_c, s3_p_c;

    always_comb begin
        s3_t1_c    = s2_r * C_INV24;
        s3_inner_c = C_INV6 + s3_t1_c[55:24];
        s3_t2_c    = s2_r * s3_inner_c;
        s3_p_c     = C_HALF + s3_t2_c[55:24];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 0; s3_p <= 0; s3_r <= 0;
            s3_r2 <= 0; s3_n <= 0; s3_underflow <= 0;
        end else begin
            s3_valid <= s2_valid; s3_p <= s3_p_c; s3_r <= s2_r;
            s3_r2 <= s2_r2; s3_n <= s2_n;
            s3_underflow <= s2_underflow;
        end
    end

    // ======================================================================
    // Stage 4: Horner 第二步 exp(r) = 1 + r + r² × p
    // ======================================================================
    logic signed [63:0] s4_t_c;
    logic signed [31:0] s4_exp_r_c;

    always_comb begin
        s4_t_c     = s3_r2 * s3_p;
        s4_exp_r_c = C_ONE + s3_r + s4_t_c[55:24];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s4_valid <= 0; s4_exp_r <= 0; s4_n <= 0; s4_underflow <= 0;
        end else begin
            s4_valid <= s3_valid; s4_exp_r <= s4_exp_r_c;
            s4_n <= s3_n; s4_underflow <= s3_underflow;
        end
    end

    // ======================================================================
    // Stage 5: 重构 exp(x) = exp(r) >> (-n), n ≤ 0
    // ======================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_valid <= 0; y_out <= 0;
        end else begin
            y_valid <= s4_valid;
            if (s4_valid) begin
                if (s4_underflow || s4_exp_r <= 0)
                    y_out <= 32'd0;
                else
                    y_out <= s4_exp_r >>> (-s4_n[31:24]);
            end
        end
    end

endmodule
```

### 5.2 online_softmax_exact.sv — 在线 Softmax 状态机

8 状态 FSM：IDLE → FIND_ROW_MAX → COMPUTE_EXP → ACCUMULATE_ROW → UPDATE_STATS → DONE（带行循环）

```systemverilog
typedef enum logic [3:0] {
    SM_IDLE, SM_FIND_ROW_MAX, SM_COMPUTE_EXP,
    SM_ACCUMULATE_ROW, SM_UPDATE_STATS, SM_DONE
} sm_state_t;
```

关键数据流：
1. FIND_ROW_MAX：逐行接收 score，缓存到 `score_buf[0:TILE_BC-1]`，同时找 max
2. COMPUTE_EXP：将 `score_buf[col] - m_new` 扩展为 Q8.24 送入 exp 流水线
3. 收集 exp 输出（5 周期延迟），流式发送 attn_weights 到 GEMM1
4. ACCUMULATE_ROW：串行累加 exp 值，更新 l
5. UPDATE_STATS：写回 m_new 和 l_new 到统计量 BRAM

### 5.3 gemm0_dot_product.sv — Q×K^T 点积阵列

Baseline 规模 Br=64, Bc=64, d=64，可以使用直接点积。

```systemverilog
// 点积循环嵌套:
// for row in 0..Br-1:
//   for col in 0..Bc-1:
//     for dim in 0..d-1:
//       S[row][col] += Q[row][dim] × K[col][dim]
//     S[row][col] = S[row][col] × (1/√d)  // 最后缩放
```

设计选择：
- 单点积顺序计算：262,144 cycles/tile × 16 tiles = 4,194,304 cycles → 超过 300k
- 32 路并行的点积：每 cycle 计算 1 个完整点积需要 d=64 cycle
  折中方案：每 cycle 并行计算 8 个 MAC，64/8 = 8 cycle/点积
  总计：8 × 4,096 × 16 = 524,288 cycle → 仍超过 300k
  推荐：每 cycle 并行 32 个 MAC，2 cycle/点积 → 131,072 cycle

### 5.4 axil_csr.sv — AXI4-Lite 控制寄存器

寄存器映射完全遵循赛题规定（Offset 0x00–0x40）：

```
0x00 CTRL[0]=START [1]=SOFT_RESET [2]=IRQ_EN
0x04 STATUS[0]=BUSY [1]=DONE [2]=ERROR
0x08 CFG[0]=CAUSAL_EN
0x14-0x30 Q/K/V/O_BASE_LO/HI (各 64 位)
0x34 STRIDE_BYTES（默认 128）
0x38 NEG_LARGE（Q8.8 的 -inf，默认 0x8000）
0x3C SCALE（1/√d = 1/8 = 0.125，Q8.8 = 0x0020）
0x40 CYCLES（只读，本次执行周期数）
```

### 5.5 causal_mask_unit.sv — Causal Mask 生成

```systemverilog
// Causal: position j > position i → mask = -inf (Q8.8: 0x8000)
//          position j ≤ position i → mask = 0 (Q8.8: 0x0000)
assign global_i = tile_i_start + local_i;
assign global_j = tile_j_start + local_j;
mask_val = (causal_en && global_j > global_i) ? Q_NEG_INF : Q_ZERO;
```

---

## 6. 验证方法论

### 6.1 测试策略

| 测试层级 | 内容 | 工具 |
|---------|------|------|
| 单元测试 | exp 单元精度 | cocotb + NumPy |
| 单元测试 | Online softmax 逐行精度 | cocotb + NumPy |
| 集成测试 | AXI4-Lite 寄存器读写 | cocotb |
| 集成测试 | DMA 读写正确性 | cocotb |
| 端到端测试 | 随机 Q/K/V（Q8.8） | cocotb + golden model |
| Corner case | Causal i=0 只能看 j=0 | 定向测试 |
| Corner case | 全零/最大值输入 | 定向测试 |

### 6.2 cocotb 验证框架

推荐 Python + cocotb（golden model 用 NumPy 编写，同一语言）：

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

误差门限验证：
- `mean_abs_error(O_dut, O_golden) < 0.03`
- `max_abs_error(O_dut, O_golden) < 0.10`

---

## 7. Cadence Genus 综合优化指南

### 7.1 SDC 约束

```tcl
# 500 MHz target (2.0 ns period)
create_clock -name clk -period 2.0 [get_ports clk]
set_clock_uncertainty 0.1 -setup [get_clocks clk]
set_clock_uncertainty 0.05 -hold [get_clocks clk]
set_input_delay -clock clk -max 0.5 [all_inputs]
set_input_delay -clock clk -min 0.1 [all_inputs]
set_output_delay -clock clk -max 0.5 [all_outputs]
set_output_delay -clock clk -min 0.1 [all_outputs]
set_false_path -from [get_ports rst_n]
```

### 7.2 面积/频率优化策略

| 策略 | 说明 |
|------|------|
| 定点而非浮点 | 16-bit 乘加器，面积远小于 FP32 |
| 分时复用乘法器 | exp 的 4 个乘法可在 GEMM 空闲时复用 |
| 充分流水线化 | 关键路径分多级，输出打一拍 reg |
| 独热码 FSM | 高速设计使用 one-hot 编码 |
| 避免大扇出 | 控制信号用 replicate register |
| SRAM 推断 | 使用 `reg [15:0] mem [0:63]` 让 Genus 推断 BRAM |

---

## 8. 代码质量标准

### 8.1 文件头注释

每个模块文件必须以完整文件头开始：

```systemverilog
// ==========================================================================
// <module_name> — <简要功能描述>
// ==========================================================================
// 作者:     <姓名>
// 日期:     <YYYY-MM-DD>
// 版本:     <版本号>
//
// 功能描述:
//   - <功能点 1>
//   - <功能点 2>
//
// 数据格式: <Q8.8 / Q8.24 / FP32 等>
// 接口:     <AXI4-Lite / AXI4-Master / 自定义>
//
// 关键设计决策:
//   - <决策 1 及原因>
//   - <决策 2 及原因>
//
// 参考:
//   - FlashAttention: https://arxiv.org/abs/2205.14135
//   - Online Normalizer: https://arxiv.org/abs/1805.02867
//   - 赛题要求: 题目要求.md
// ==========================================================================
```

### 8.2 命名规范

| 对象 | 规范 | 示例 |
|------|------|------|
| 模块名 | snake_case | `pipelined_exp_fixed` |
| 参数 | UPPER_SNAKE_CASE | `TILE_BR`, `DATA_WIDTH` |
| 信号 | snake_case + 语义后缀 | `score_valid`, `exp_ops_count` |
| FSM 状态 | UPPER_SNAKE_CASE | `SM_IDLE`, `MAIN_GEMM0` |
| 常量 | C_ 前缀 + UPPER_SNAKE | `C_LN2`, `C_INV_LN2` |
| 寄存器 | _q 后缀（时序） | `state_q`, `counter_q` |
| 低有效信号 | _n 后缀 | `rst_n` |

### 8.3 代码结构规范

每个模块按此顺序组织：
1. 模块声明 + 参数
2. 端口声明（分组：时钟复位、控制、数据输入、数据输出）
3. 局部参数（localparam）
4. 类型定义（typedef enum）
5. 信号声明
6. 子模块实例化
7. always_comb 块
8. always_ff 块
9. assign 连续赋值
10. 断言（`ifdef SIMULATION` 包裹）

### 8.4 SystemVerilog 设计原则

- 组合逻辑用 `always_comb` + 阻塞赋值 `=`
- 时序逻辑用 `always_ff` + 非阻塞赋值 `<=`
- 每个 `case` 必须有 `default`
- 所有寄存器在 reset 中赋已知值（禁止 X 传播）
- 模块输出尽量打一拍 reg
- 禁止使用 `full_case` / `parallel_case`
- 参数化所有位宽和深度

---

## 9. 性能分析方法

### 9.1 理论最小 Cycle 数

S=256, d=64, Br=Bc=64：

```
Tiles = 4 × 4 = 16 tiles
每 tile:
  GEMM0: 64×64×64 = 262,144 MAC
  Softmax: 64×64 = 4,096 exp
  GEMM1: 64×64×64 = 262,144 MAC
总计 MAC: 2 × 16 × 262,144 = 8,388,608

若需 < 300k cycles: 8,388,608 / 300,000 ≈ 28 MAC/cycle 并行度
推荐: 32 路并行点积
```

### 9.2 带宽分析

```
基准数据量: Q(32KB) + K(32KB) + V(32KB) + O(32KB) = 128KB

Tile 复用 (Br=Bc=64):
  RD_BYTES = |Q| + |K|×4 + |V|×4 + |O|
           = 32 + 128 + 128 + 32 = 320 KB
  WR_BYTES = |O| = 32 KB

核心收益：消除 S×S (256KB) 的片上存储需求
```

---

## 10. 与参考示例代码的关系

示例(不符合题目仅作参考)/ 来自 `flashattn-softmax-engine`。

**关键差异**：

| 方面 | 参考示例 | 本赛题 Baseline |
|------|---------|----------------|
| 数据格式 | FP32 | Q8.8 定点 |
| 规模 | d=128 | d=64 |
| 接口 | AXI4-Lite 控制 | AXI4-Lite + AXI4-Master DMA |
| GEMM | 仅 softmax | 完整 GEMM0+GEMM1 |
| Tile | Br=Bc=128 | Br=Bc=64 |
| 综合 | Vivado | Cadence Genus |

**可参考**：exp 的 5 级流水线架构（需将 FP32 输入改为 Q8.24 定点）。

---

## 11. 开发阶段

| 阶段 | 任务 |
|------|------|
| Phase 1: 算法建模 | Python golden model + Q8.8 量化 + 误差分析 |
| Phase 2: 核心 RTL | exp 流水线、online softmax FSM、GEMM0/GEMM1 |
| Phase 3: 接口集成 | AXI4-Lite CSR、AXI4-Master DMA、Tile 预取器 |
| Phase 4: 验证 | cocotb 环境、Golden 对比、Corner case |
| Phase 5: 综合优化 | Genus 综合、SDC、面积/频率迭代 |
| Phase 6: 文档 | 设计文档、性能分析、提交材料 |
| Bonus | BF16/FP16、多 head、更长序列、AXI4-Stream 等 |

---

## 12. 常见陷阱

1. **Q8.8 溢出**：64 次乘积累加需 ≥40-bit 累加器
2. **exp 下溢**：x < ~-88.7 时 exp→0，需下溢保护
3. **Causal mask 时序**：mask 必须在 GEMM0 同时应用
4. **l 精度**：分母累加使用 Q16.16+
5. **m rescale**：m 更新时 O 的 rescale 影响最终精度
6. **AXI4 握手**：正确处理 VALID/READY BACKPRESSURE
7. **Genus SRAM**：二维 reg 数组可能推断为寄存器，注意 BRAM 推断语法
8. **不要照搬参考示例**：FP32→Q8.8、加 GEMM、加 DMA 是必须做的改动
