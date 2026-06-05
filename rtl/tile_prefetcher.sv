// ==========================================================================
// tile_prefetcher — Tile 预取器 + 双缓冲 SRAM 管理
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 管理 K tile buffer (64×64×16bit = 8KB BRAM)
//   - 管理 V tile buffer (64×64×16bit = 8KB BRAM)
//   - 管理 Q tile buffer (64×64×16bit = 8KB BRAM)
//   - 管理 O 累加 buffer (64×64×32bit = 16KB BRAM)
//   - 管理 m/l 统计量 SRAM (256×2×32bit = 2KB BRAM)
//   - 协调 DMA 引擎进行 tile 数据的加载和写回
//   - 支持双缓冲 (double-buffering) 实现 DMA 与计算重叠
//
// 数据格式:
//   K/V/Q Buffer:   16-bit Q8.8
//   O 累加器:       32-bit Q16.16
//   m 统计量:       32-bit Q8.24
//   l 统计量:       32-bit Q16.16
//
// 接口: DMA 控制接口, SRAM 读写接口
//
// 架构:
//   K_BUF: reg [15:0] k_buf [0:BC-1][0:D-1] 合成 1D 地址 = row*D+col
//   V_BUF: reg [15:0] v_buf [0:BC-1][0:D-1]
//   Q_BUF: reg [15:0] q_buf [0:BR-1][0:D-1]
//   O_ACC: reg [31:0] o_acc [0:BR-1][0:D-1]
//   STAT_M: reg [31:0] stat_m [0:S-1]      (256×32bit)
//   STAT_L: reg [31:0] stat_l [0:S-1]      (256×32bit)
//
// 关键设计决策:
//   - K/V Buffer 在 K/V tile 切换时更新, 跨 4 个 Q tile 复用
//   - Q Buffer 在每个 Q tile 时更新
//   - O 累加器保持 Q16.16 直到最终写回前才量化为 Q8.8
//   - 使用 2D→1D 地址转换: addr_1d = row × COLS + col
//   - 双缓冲: 下一 tile DMA 与当前 tile 计算可重叠
//
// 参考:
//   - 赛题要求: ../题目要求.md §2.1(7) (存储约束)
//   - 架构设计: ../docs/ARCHITECTURE.md §2.2
// ==========================================================================

`ifndef TILE_PREFETCHER_SV
`define TILE_PREFETCHER_SV

`timescale 1ns / 1ps

module tile_prefetcher #(
    parameter int S            = 256,   // 序列长度
    parameter int D            = 64,    // Head 维度
    parameter int BR           = 64,    // Q tile 行数
    parameter int BC           = 64,    // K/V tile 列数
    parameter int Q8P8_WIDTH   = 16,    // Q8.8 位宽
    parameter int Q16P16_WIDTH = 32     // Q16.16 位宽
) (
    // ---- 时钟 & 复位 ----
    input  logic                         clk,
    input  logic                         rst_n,

    // ==================================================================
    // 控制接口 (来自顶层 FSM)
    // ==================================================================
    input  logic                         load_kv_start,    // 启动加载 K/V tile
    input  logic                         load_q_start,     // 启动加载 Q tile
    input  logic                         writeback_start,  // 启动写回 O tile
    input  logic [15:0]                  tile_j_start,     // K/V tile 起始列 (全局)
    input  logic [15:0]                  tile_i_start,     // Q tile 起始行 (全局)
    output logic                         load_kv_done,     // K/V 加载完成
    output logic                         load_q_done,      // Q 加载完成
    output logic                         writeback_done,   // 写回完成

    // ==================================================================
    // 统计量 SRAM 控制
    // ==================================================================
    input  logic                         stat_init_start,  // 初始化统计量 (m=-inf, l=0)
    output logic                         stat_init_done,   // 初始化完成
    // 统计量读写 (来自 online_softmax_exact)
    input  logic [7:0]                   stat_addr,        // 行地址 [0, 255]
    input  logic                         stat_wr_en,       // 写使能
    input  logic signed [31:0]           stat_m_wr,        // m (Q8.24)
    input  logic signed [31:0]           stat_l_wr,        // l (Q16.16)
    output logic signed [31:0]           stat_m_rd,        // m 读出
    output logic signed [31:0]           stat_l_rd,        // l 读出

    // ==================================================================
    // K Tile Buffer 接口
    // ==================================================================
    // 写端口 (DMA 加载)
    input  logic                         k_buf_wr_en,
    input  logic [$clog2(BC*D)-1:0]      k_buf_wr_addr,
    input  logic signed [Q8P8_WIDTH-1:0] k_buf_wr_data,
    // 读端口 (GEMM0 读取)
    input  logic [$clog2(BC*D)-1:0]      k_buf_rd_addr,
    output logic signed [Q8P8_WIDTH-1:0] k_buf_rd_data,

    // ==================================================================
    // V Tile Buffer 接口
    // ==================================================================
    input  logic                         v_buf_wr_en,
    input  logic [$clog2(BC*D)-1:0]      v_buf_wr_addr,
    input  logic signed [Q8P8_WIDTH-1:0] v_buf_wr_data,
    input  logic [$clog2(BC*D)-1:0]      v_buf_rd_addr,
    output logic signed [Q8P8_WIDTH-1:0] v_buf_rd_data,

    // ==================================================================
    // Q Tile Buffer 接口
    // ==================================================================
    input  logic                         q_buf_wr_en,
    input  logic [$clog2(BR*D)-1:0]      q_buf_wr_addr,
    input  logic signed [Q8P8_WIDTH-1:0] q_buf_wr_data,
    input  logic [$clog2(BR*D)-1:0]      q_buf_rd_addr,
    output logic signed [Q8P8_WIDTH-1:0] q_buf_rd_data,

    // ==================================================================
    // O 累加器接口 (GEMM1 读写 + DMA 写回读取)
    // ==================================================================
    input  logic                         o_acc_wr_en,
    input  logic [$clog2(BR*D)-1:0]      o_acc_wr_addr,
    input  logic signed [Q16P16_WIDTH-1:0] o_acc_wr_data,
    input  logic [$clog2(BR*D)-1:0]      o_acc_rd_addr,
    output logic signed [Q16P16_WIDTH-1:0] o_acc_rd_data,

    // ==================================================================
    // DMA 引擎接口
    // ==================================================================
    output logic                         dma_req_rd,        // DMA 读请求
    output logic                         dma_req_wr,        // DMA 写请求
    output logic [63:0]                  dma_base_addr,     // DMA 基地址
    output logic [15:0]                  dma_tile_rows,     // Tile 行数
    output logic [15:0]                  dma_tile_cols,     // Tile 列数
    output logic [15:0]                  dma_row_stride,    // 行 stride
    input  logic                         dma_done,          // DMA 完成
    input  logic                         dma_error          // DMA 错误
);

    // ======================================================================
    // SRAM 存储体 (推断为 BRAM)
    // ======================================================================
    // K Buffer: reg [15:0] k_buf [0:BC-1][0:D-1];   // 64×64
    // V Buffer: reg [15:0] v_buf [0:BC-1][0:D-1];
    // Q Buffer: reg [15:0] q_buf [0:BR-1][0:D-1];
    // O 累加器: reg [31:0] o_acc [0:BR-1][0:D-1];   // 64×64×32bit
    // 统计量 m: reg [31:0] stat_m [0:S-1];            // 256×32bit
    // 统计量 l: reg [31:0] stat_l [0:S-1];            // 256×32bit

    // ======================================================================
    // 地址转换: 2D (row, col) → 1D addr
    // ======================================================================
    // k_buf_addr_1d = row × D + col   (BC=64, D=64 → 12-bit addr)
    // v_buf_addr_1d = row × D + col
    // q_buf_addr_1d = row × D + col   (BR=64, D=64 → 12-bit addr)
    // o_acc_addr_1d = row × D + col
    // stat_addr = row                  (直接行索引, 8-bit addr)

    // ======================================================================
    // DMA 协调逻辑
    // ======================================================================
    // - load_kv_start → DMA 读取 K/V 到 k_buf/v_buf
    // - load_q_start  → DMA 读取 Q 到 q_buf
    // - writeback_start → DMA 从 o_acc 读, 量化后写回

    // ======================================================================
    // 统计量初始化: m = -inf (0xFF800000), l = 0x00000000
    // ======================================================================

endmodule

`endif // TILE_PREFETCHER_SV
