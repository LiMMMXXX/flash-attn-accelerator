// ==========================================================================
// causal_mask_unit — Causal Attention Mask 生成单元
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 生成 causal attention mask: M[i][j] = -inf (j > i) 或 0 (j ≤ i)
//   - 支持 tile 内的局部坐标到全局坐标的映射
//   - 1 cycle 延迟的 mask 输出
//
// 数据格式:
//   输出: Q8.8 (16-bit), -inf = 0x8000, 0 = 0x0000
//
// 接口: 组合逻辑/1-cycle流水
//
// 关键设计决策:
//   - mask 在 GEMM0 输出 score 前叠加, 避免先计算后 mask 浪费 cycle
//   - 全局坐标 = tile 起始偏移 + tile 内局部坐标
//
// 参考:
//   - 赛题要求:  题目要求.md (Causal mask 为 Baseline 必须支持)
//   - 架构设计:  docs/ARCHITECTURE.md
// ==========================================================================

`ifndef CAUSAL_MASK_UNIT_SV
`define CAUSAL_MASK_UNIT_SV

`timescale 1ns / 1ps

module causal_mask_unit #(
    parameter int MAX_SEQ_LEN = 256   // 最大序列长度
) (
    // ---- 时钟 & 复位 ----
    input  logic                         clk,
    input  logic                         rst_n,

    // ---- 控制接口 ----
    input  logic                         causal_en,      // Causal mask 使能

    // ---- 坐标输入 ----
    input  logic [15:0]                  tile_i_start,   // Q tile 全局起始行
    input  logic [15:0]                  tile_j_start,   // K tile 全局起始列
    input  logic [15:0]                  local_i,        // Q 在 tile 内的行 [0, Br)
    input  logic [15:0]                  local_j,        // K 在 tile 内的列 [0, Bc)

    // ---- 请求/响应 ----
    input  logic                         mask_req,       // Mask 请求
    output logic signed [15:0]           mask_val        // Mask 值 (Q8.8: 0 或 -inf)
);

    // ======================================================================
    // Mask 逻辑:
    //   global_i = tile_i_start + local_i
    //   global_j = tile_j_start + local_j
    //   if (causal_en && global_j > global_i) → -inf, else → 0
    // ======================================================================

endmodule

`endif // CAUSAL_MASK_UNIT_SV
