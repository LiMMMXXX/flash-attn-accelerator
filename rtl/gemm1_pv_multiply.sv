// ==========================================================================
// gemm1_pv_multiply — GEMM1: P × V 累加 (含 Online Rescale)
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 计算 O += P × V, 其中 P = attn_weights [Br, Bc], V = V_tile [Bc, d]
//   - 实现 online rescale: 当 m_new > m_old 时, O_old × exp(m_old - m_new)
//   - 64 路并行 MAC 阵列, 累加到 O_acc [Br, d] (Q16.16 精度)
//
// 数据格式:
//   输入 P (attn_weight): Q8.8 (16-bit)
//   输入 V:                Q8.8 (16-bit)
//   O 累加器:              Q16.16 (32-bit)
//   输出 O (最终):          Q8.8 (16-bit)
//
// 接口: 流式 P 输入 (来自 softmax), SRAM V 读取, O 累加器读写
//
// 架构:
//   64 个并行 MAC → 每个 MAC 对应一个 (row, dim) 组合
//   O_acc[row][dim] += P[row][col] × V[col][dim]
//   Rescale: O_acc[row][dim] = O_acc[row][dim] × exp(m_old - m_new)
//
// 关键设计决策:
//   - 64 路并行匹配 d=64, 达到 1 result/cycle
//   - O 累加使用 Q16.16 防止多次 tile 累加的精度损失
//   - Rescale 复用 pipelined_exp_fixed 计算 exp(m_old - m_new)
//   - 最终归一化 (除以 l) 延迟到 writeback 阶段
//
// 参考:
//   - 赛题要求: ../题目要求.md
//   - 架构设计: ../docs/ARCHITECTURE.md
// ==========================================================================

`ifndef GEMM1_PV_MULTIPLY_SV
`define GEMM1_PV_MULTIPLY_SV

`timescale 1ns / 1ps

module gemm1_pv_multiply #(
    parameter int BR           = 64,    // Q tile 行数
    parameter int BC           = 64,    // K/V tile 列数
    parameter int D            = 64,    // Head 维度
    parameter int Q8P8_WIDTH   = 16,    // Q8.8 位宽
    parameter int Q16P16_WIDTH = 32,    // Q16.16 位宽
    parameter int ACC_WIDTH    = 40     // 累加器位宽
) (
    // ---- 时钟 & 复位 ----
    input  logic                         clk,
    input  logic                         rst_n,

    // ---- 控制接口 ----
    input  logic                         start,          // 启动 GEMM1
    output logic                         done,           // GEMM1 完成
    output logic                         busy,           // 忙碌标志

    // ---- P 输入 (attn_weight, Q8.8, 来自 softmax) ----
    input  logic signed [Q8P8_WIDTH-1:0] attn_weight,    // P_ij (Q8.8)
    input  logic                         attn_valid,     // 有效标志
    input  logic [15:0]                  attn_row,       // 行 [0, Br)
    input  logic [15:0]                  attn_col,       // 列 [0, Bc)
    input  logic                         attn_last,      // 最后一个 P 元素

    // ---- V 输入 (Q8.8, 从 SRAM 读取) ----
    output logic [$clog2(BC*D)-1:0]      v_sram_addr,    // V SRAM 地址
    input  logic signed [Q8P8_WIDTH-1:0] v_elem,         // V 元素 (Q8.8)

    // ---- Online Rescale 统计量 (来自 softmax) ----
    input  logic signed [31:0]           m_old_ext,      // m_old (Q8.24)
    input  logic signed [31:0]           m_new_ext,      // m_new (Q8.24)
    input  logic signed [31:0]           l_old_ext,      // l_old (Q16.16)

    // ---- O 累加器接口 (Q16.16) ----
    output logic [$clog2(BR*D)-1:0]      o_acc_addr,     // 累加器地址
    output logic                         o_acc_wr_en,    // 写使能
    output logic signed [Q16P16_WIDTH-1:0] o_acc_wr_data, // 写数据 (Q16.16)
    input  logic signed [Q16P16_WIDTH-1:0] o_acc_rd_data, // 读数据 (Q16.16)

    // ---- 最终 O 输出 (Q8.8, 通往 quantize) ----
    output logic signed [Q8P8_WIDTH-1:0] o_q8p8_out,     // O 元素 (Q8.8)
    output logic                         o_valid,        // O 有效
    output logic [15:0]                  o_row,          // O 行
    output logic [15:0]                  o_col           // O 列
);

    // ======================================================================
    // 子模块: pipelined_exp_fixed (用于 rescale 的 exp(m_old-m_new))
    // ======================================================================
    // exp_rescale = exp(m_old - m_new), m_old ≤ m_new → m_old - m_new ≤ 0

    // ======================================================================
    // 64 路并行 MAC 阵列
    // ======================================================================
    // O_acc[row][dim] += P[row][col] × V[col][dim]

    // ======================================================================
    // Rescale 逻辑
    // ======================================================================
    // if (m_new > m_old):
    //   fa = exp(m_old - m_new)  (Q8.24)
    //   O_acc[row][dim] = O_acc[row][dim] × fa  (Q16.16 × Q8.24 → Q16.16)

    // ======================================================================
    // 状态机
    // ======================================================================
    // IDLE → RESCALE (if needed) → COMPUTE → DONE

endmodule

`endif // GEMM1_PV_MULTIPLY_SV
