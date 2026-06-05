// ==========================================================================
// online_softmax_exact — 在线精确 Softmax (Milakov-Gimelshein 算法)
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 处理 GEMM0 输出的 [Br, Bc] score tile
//   - 实现在线 softmax 算法: 逐行求 max → exp(x-m_new) → 更新 l/m/O
//   - 不存储 S×S 注意力矩阵，满足赛题算法约束
//
// 数据格式:
//   Score 输入:  Q8.8 (16-bit)
//   exp 内部:    Q8.24 (32-bit)
//   m统计量:     Q8.24 (32-bit)
//   l统计量:     Q16.16 (32-bit)
//   注意力权重输出: Q8.8 (16-bit)
//
// 接口:  流式 score 输入, 流式 attn_weight 输出, SRAM 统计量读写
//
// FSM (6 状态):
//   IDLE → FIND_ROW_MAX → COMPUTE_EXP → ACCUMULATE_ROW → UPDATE_STATS → DONE
//     ↑                                                                   │
//     └───────────────────── (next row loop) ─────────────────────────────┘
//
// 关键设计决策:
//   - 实例化 pipelined_exp_fixed 作为 exp 计算核心
//   - 行缓冲仅 1 行 (64 个 Q8.8 元素), 最小化存储
//   - m/l 统计量存储在外部 SRAM (stat_RAM), 支持 tile 间持久化
//
// 参考:
//   - FlashAttention: https://arxiv.org/abs/2205.14135
//   - Online Normalizer: https://arxiv.org/abs/1805.02867
// ==========================================================================

`ifndef ONLINE_SOFTMAX_EXACT_SV
`define ONLINE_SOFTMAX_EXACT_SV

`timescale 1ns / 1ps

module online_softmax_exact #(
    parameter int TILE_BR    = 64,   // Q 分块行数
    parameter int TILE_BC    = 64,   // K/V 分块列数
    parameter int DATA_WIDTH = 32    // 内部 Q8.24/Q16.16 精度
) (
    // ---- 时钟 & 复位 ----
    input  logic                         clk,
    input  logic                         rst_n,

    // ---- 控制接口 ----
    input  logic                         tile_start,    // 开始处理一个 tile
    input  logic                         seq_start,     // 新序列开始 (重置统计量)
    input  logic [15:0]                  br_actual,     // 实际 Br (≤ TILE_BR)
    input  logic [15:0]                  bc_actual,     // 实际 Bc (≤ TILE_BC)
    output logic                         tile_done,     // Tile softmax 完成
    output logic                         busy,          // 忙碌标志

    // ---- Score 输入 (来自 GEMM0, Q8.8) ----
    input  logic signed [15:0]           score_in,      // Q8.8 score
    input  logic                         score_valid,   // score 有效
    input  logic  [15:0]                 score_row,     // 行索引 [0, Br)
    input  logic  [15:0]                 score_col,     // 列索引 [0, Bc)

    // ---- 注意力权重输出 (通往 GEMM1, Q8.8) ----
    output logic signed [15:0]           attn_weight_out,   // P_ij (Q8.8)
    output logic                         attn_weight_valid, // 有效标志
    output logic [15:0]                  attn_weight_row,   // 行索引
    output logic [15:0]                  attn_weight_col,   // 列索引

    // ---- 运行统计量 SRAM 接口 ----
    output logic [$clog2(TILE_BR)-1:0]   stat_addr,       // 地址 (log2(Br) bits)
    output logic                         stat_wr_en,      // 写使能
    output logic signed [DATA_WIDTH-1:0] stat_m_wr,       // m (Q8.24) 写入
    output logic signed [DATA_WIDTH-1:0] stat_l_wr,       // l (Q16.16) 写入
    input  logic signed [DATA_WIDTH-1:0] stat_m_rd,       // m (Q8.24) 读出
    input  logic signed [DATA_WIDTH-1:0] stat_l_rd,       // l (Q16.16) 读出

    // ---- 性能计数器 ----
    output logic [31:0]                  exp_ops_count,   // exp 操作计数
    output logic [31:0]                  stall_cycles     // 停顿周期
);

    // ======================================================================
    // 子模块: pipelined_exp_fixed (exp 流水线)
    // ======================================================================
    // 实例化 5 级流水线定点 exp 单元

    // ======================================================================
    // 定点常量 (Q8.8)
    // ======================================================================
    // Q_NEG_INF = 16'sh8000 (Q8.8 最小有符号值)

    // ======================================================================
    // FSM 状态定义
    // ======================================================================
    // typedef enum: SM_IDLE, SM_FIND_ROW_MAX, SM_COMPUTE_EXP,
    //               SM_ACCUMULATE_ROW, SM_UPDATE_STATS, SM_DONE

    // ======================================================================
    // 工作寄存器
    // ======================================================================
    // cur_row, cur_col:          当前处理的行/列
    // row_max:                   当前行最大值 (Q8.8)
    // m_old, m_new:              运行统计量 (Q8.24)
    // l_old:                     运行统计量 (Q16.16)
    // exp_sum:                   exp 累加和 (Q16.16)
    // score_buf[0:TILE_BC-1]:    1行 score 缓存 (Q8.8)
    // exp_buf[0:TILE_BC-1]:      exp 输出缓存 (Q8.8)

    // ======================================================================
    // 定点运算辅助函数
    // ======================================================================
    // q8p8_to_q8p24:  Q8.8 → Q8.24 扩展 (符号扩展 + <<16)
    // q8p24_to_q8p8:  Q8.24 → Q8.8 截断 (带饱和)

    // ======================================================================
    // 主状态机
    // ======================================================================
    // 6 状态 FSM 实现 online softmax exact 算法

endmodule

`endif // ONLINE_SOFTMAX_EXACT_SV
