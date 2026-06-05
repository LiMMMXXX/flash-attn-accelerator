// ==========================================================================
// gemm0_dot_product — GEMM0: Q × K^T 点积阵列
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 计算 S = Q × K^T × (1/√d)
//   - Q: [Br, d] Q8.8, K: [d, Bc] Q8.8 → Score: [Br, Bc] Q8.8
//   - 64 路并行 MAC 阵列, 每个 cycle 计算一个完整点积
//   - 在 score 输出前叠加 causal mask
//
// 数据格式:
//   输入 Q/K:  Q8.8 (16-bit)
//   累加器:    40-bit (64 × Q8.8×Q8.8 不溢出)
//   输出 Score: Q8.8 (16-bit), 经 1/√d 缩放后截断
//
// 接口: 流式 Q 输入, SRAM K 读取, 流式 Score 输出
//
// 架构:
//   64 个并行 MAC → 每个 MAC 对应一个 (Q_row, K_col) 组合
//   每 cycle: Q[row][dim] × K[col][dim] → 累加到 acc[row][col]
//   64 cycles 后完成所有 d=64 维度的点积 → 输出 Score[row][col]
//
// 关键设计决策:
//   - 64路并行匹配 d=64, 每个点积仅需 1 pass
//   - 40-bit 累加器防止 64 次 Q8.8×Q8.8 累加溢出
//   - Causal mask 在最后阶段叠加, 不消耗额外 cycle
//   - 1/√d 缩放: 预计算为 Q8.8 常数 (0.125 = 0x0020)
//
// 参考:
//   - 赛题要求: ../题目要求.md
//   - 架构设计: ../docs/ARCHITECTURE.md
// ==========================================================================

`ifndef GEMM0_DOT_PRODUCT_SV
`define GEMM0_DOT_PRODUCT_SV

`timescale 1ns / 1ps

module gemm0_dot_product #(
    parameter int BR           = 64,    // Q tile 行数
    parameter int BC           = 64,    // K tile 列数
    parameter int D            = 64,    // Head 维度
    parameter int Q8P8_WIDTH   = 16,    // Q8.8 位宽
    parameter int ACC_WIDTH    = 40     // 累加器位宽 (防溢出)
) (
    // ---- 时钟 & 复位 ----
    input  logic                         clk,
    input  logic                         rst_n,

    // ---- 控制接口 ----
    input  logic                         start,         // 启动 GEMM0
    output logic                         done,          // GEMM0 完成
    output logic                         busy,          // 忙碌标志

    // ---- Q 输入 (Q8.8, 流式) ----
    input  logic signed [Q8P8_WIDTH-1:0] q_elem,        // Q 元素 (Q8.8)
    input  logic                         q_valid,       // Q 有效
    input  logic [15:0]                  q_row,         // Q 行 [0, Br)
    input  logic [15:0]                  q_col,         // Q 列 [0, d)

    // ---- K 输入 (Q8.8, 从 SRAM 读取) ----
    output logic [$clog2(BC*D)-1:0]      k_sram_addr,   // K SRAM 地址
    input  logic signed [Q8P8_WIDTH-1:0] k_elem,        // K 元素 (Q8.8)

    // ---- Causal Mask 接口 ----
    input  logic                         causal_en,     // Causal mask 使能
    input  logic [15:0]                  tile_i_start,  // 当前 Q tile 全局起始行
    input  logic [15:0]                  tile_j_start,  // 当前 K tile 全局起始列

    // ---- Score 输出 (Q8.8, 流式) ----
    output logic signed [Q8P8_WIDTH-1:0] score_out,     // Score 值 (Q8.8)
    output logic                         score_valid,   // Score 有效
    output logic [15:0]                  score_row,     // Score 行 [0, Br)
    output logic [15:0]                  score_col,     // Score 列 [0, Bc)
    output logic                         score_last,    // 最后一个 score

    // ---- 缩放因子 ----
    input  logic signed [Q8P8_WIDTH-1:0] inv_sqrt_d     // 1/√d (Q8.8) = 0.125
);

    // ======================================================================
    // 64 路并行 MAC 阵列
    // ======================================================================
    // 每路对应一个 (row, col) 组合
    // 累加器: acc[row][col] = Σ_dim Q[row][dim] × K[col][dim]

    // ======================================================================
    // 状态机
    // ======================================================================
    // IDLE → COMPUTE → DONE
    // COMPUTE 中: 64 cycles 完成所有 d=64 维度

    // ======================================================================
    // Causal Mask 逻辑
    // ======================================================================
    // global_i = tile_i_start + score_row
    // global_j = tile_j_start + score_col
    // mask_val = (causal_en && global_j > global_i) ? -inf : 0

endmodule

`endif // GEMM0_DOT_PRODUCT_SV
