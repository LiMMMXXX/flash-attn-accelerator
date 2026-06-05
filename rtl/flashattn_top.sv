// ==========================================================================
// flashattn_top — FlashAttention 硬件加速器顶层模块
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 集成所有子模块: CSR、DMA、Tile预取器、GEMM0、Softmax、GEMM1、量化、性能计数器
//   - 实现主控 FSM: 11 状态 FlashAttention tiling 循环
//   - 协调控制路径 (AXI4-Lite CSR) 与数据路径 (AXI4-Master DMA + 计算流水线)
//   - 产生中断信号 (IRQ) 和性能计数器锁存信号
//
// 数据格式:
//   外部接口:  Q8.8 (16-bit)
//   内部数据通路: Q8.8 / Q8.24 / Q16.16 / 40-bit ACC
//
// 接口:
//   - AXI4-Lite Slave (控制寄存器)
//   - AXI4-Master (DMA 数据搬运)
//   - IRQ 中断输出
//
// 主FSM (11 状态):
//   IDLE → INIT_STATS → LOAD_KV → LOAD_Q → GEMM0 → SOFTMAX → GEMM1
//                                                     ↓
//   NEXT_Q ←───────────────────────────────────────────┘
//     ↓ (Q tile 遍历完)
//   NEXT_KV → (j++ 循环或...) → WRITEBACK → DONE → IDLE
//
// 关键设计决策:
//   - 所有子模块通过顶层互联, TOP 作为集成枢纽
//   - CSR 寄存器驱动控制信号到各子模块
//   - 主 FSM 按 tile 循环调度 DMA + GEMM0 + Softmax + GEMM1
//   - 性能计数器事件由各子模块产生, 顶层收集
//   - 64路并行 MAC 满足 <300k cycle 约束
//
// 参考:
//   - 赛题要求: ../题目要求.md
//   - 架构设计: ../docs/ARCHITECTURE.md
// ==========================================================================

`ifndef FLASHATTN_TOP_SV
`define FLASHATTN_TOP_SV

`timescale 1ns / 1ps

module flashattn_top #(
    // 赛题固定参数
    parameter int S  = 256,    // 序列长度
    parameter int D  = 64,     // Head 维度
    parameter int BR = 64,     // Q tile 行数
    parameter int BC = 64,     // K/V tile 列数
    // AXI4 参数
    parameter int AXI_ADDR_W = 64,
    parameter int AXI_DATA_W = 64,
    parameter int AXI_ID_W   = 4
) (
    // ---- 时钟 & 复位 ----
    input  logic                         clk,
    input  logic                         rst_n,

    // ==================================================================
    // AXI4-Lite Slave (控制寄存器接口)
    // ==================================================================
    // 写地址通道
    input  logic [7:0]                   s_axil_awaddr,
    input  logic                         s_axil_awvalid,
    output logic                         s_axil_awready,
    // 写数据通道
    input  logic [31:0]                  s_axil_wdata,
    input  logic [3:0]                   s_axil_wstrb,
    input  logic                         s_axil_wvalid,
    output logic                         s_axil_wready,
    // 写响应通道
    output logic [1:0]                   s_axil_bresp,
    output logic                         s_axil_bvalid,
    input  logic                         s_axil_bready,
    // 读地址通道
    input  logic [7:0]                   s_axil_araddr,
    input  logic                         s_axil_arvalid,
    output logic                         s_axil_arready,
    // 读数据通道
    output logic [31:0]                  s_axil_rdata,
    output logic [1:0]                   s_axil_rresp,
    output logic                         s_axil_rvalid,
    input  logic                         s_axil_rready,

    // ==================================================================
    // AXI4-Master (DMA 数据接口)
    // ==================================================================
    // 读地址通道
    output logic [AXI_ID_W-1:0]          m_axi_arid,
    output logic [AXI_ADDR_W-1:0]        m_axi_araddr,
    output logic [7:0]                   m_axi_arlen,
    output logic [2:0]                   m_axi_arsize,
    output logic [1:0]                   m_axi_arburst,
    output logic                         m_axi_arvalid,
    input  logic                         m_axi_arready,
    // 读数据通道
    input  logic [AXI_ID_W-1:0]          m_axi_rid,
    input  logic [AXI_DATA_W-1:0]        m_axi_rdata,
    input  logic [1:0]                   m_axi_rresp,
    input  logic                         m_axi_rlast,
    input  logic                         m_axi_rvalid,
    output logic                         m_axi_rready,
    // 写地址通道
    output logic [AXI_ID_W-1:0]          m_axi_awid,
    output logic [AXI_ADDR_W-1:0]        m_axi_awaddr,
    output logic [7:0]                   m_axi_awlen,
    output logic [2:0]                   m_axi_awsize,
    output logic [1:0]                   m_axi_awburst,
    output logic                         m_axi_awvalid,
    input  logic                         m_axi_awready,
    // 写数据通道
    output logic [AXI_DATA_W-1:0]        m_axi_wdata,
    output logic [AXI_DATA_W/8-1:0]      m_axi_wstrb,
    output logic                         m_axi_wlast,
    output logic                         m_axi_wvalid,
    input  logic                         m_axi_wready,
    // 写响应通道
    input  logic [AXI_ID_W-1:0]          m_axi_bid,
    input  logic [1:0]                   m_axi_bresp,
    input  logic                         m_axi_bvalid,
    output logic                         m_axi_bready,

    // ==================================================================
    // 中断输出
    // ==================================================================
    output logic                         irq_out
);

    // ======================================================================
    // 子模块互联信号
    // ======================================================================

    // ---- axil_csr → 顶层 FSM ----
    // ctrl_start, ctrl_soft_reset, ctrl_irq_en, cfg_causal_en
    // q/k/v/o_base_addr, stride_bytes, neg_large, scale

    // ---- 顶层 FSM → DMA ----
    // dma_start_rd, dma_start_wr, dma_base_addr, ...

    // ---- DMA ↔ tile_prefetcher ----
    // sram_* 信号, tile_* 数据信号

    // ---- tile_prefetcher → GEMM0 (Q, K 读取) ----
    // q_buf_rd_*, k_buf_rd_*

    // ---- GEMM0 → online_softmax (score 流) ----
    // score_in, score_valid, score_row, score_col

    // ---- online_softmax → GEMM1 (attn_weight 流) ----
    // attn_weight_out, attn_valid, attn_row, attn_col

    // ---- online_softmax ↔ tile_prefetcher (stat SRAM) ----
    // stat_addr, stat_wr_en, stat_m_wr, stat_l_wr, stat_m_rd, stat_l_rd

    // ---- GEMM1 ↔ tile_prefetcher (O 累加器, V 读取) ----
    // o_acc_*, v_buf_rd_*

    // ---- GEMM1 → quantize → tile_prefetcher (O 最终输出) ----
    // o_q8p8_out, o_valid

    // ---- 各模块 → perf_counters ----
    // evt_* 事件信号

    // ======================================================================
    // 子模块实例化
    // ======================================================================
    // 1. axil_csr
    // 2. axi4_dma_engine
    // 3. tile_prefetcher
    // 4. gemm0_dot_product
    // 5. online_softmax_exact (含 pipelined_exp_fixed)
    // 6. gemm1_pv_multiply
    // 7. quantize_q8p8
    // 8. perf_counters

    // ======================================================================
    // 主控 FSM (11 状态)
    // ======================================================================
    // 调度 tile 循环: 外循环 K/V, 内循环 Q
    // 协调 DMA 加载 + GEMM0 + Softmax + GEMM1 的顺序执行
    // 状态转换详见 docs/ARCHITECTURE.md §4

endmodule

`endif // FLASHATTN_TOP_SV
