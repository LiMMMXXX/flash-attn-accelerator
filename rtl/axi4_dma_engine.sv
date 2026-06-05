// ==========================================================================
// axi4_dma_engine — AXI4-Master DMA 引擎
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 从 DDR 读取 Q/K/V tile 数据到 SRAM buffer (AXI4 Read)
//   - 将 SRAM buffer 中的 O 结果写回 DDR (AXI4 Write)
//   - 支持可配置 burst 长度
//   - 64-bit AXI4 数据宽度, 每 beat 传输 4 个 Q8.8 元素
//
// 数据格式:
//   AXI4 数据: 64-bit (4 × Q8.8)
//   地址计算: base + row×stride + col×2
//
// 接口: AXI4-Master 全5通道 (读地址/读数据/写地址/写数据/写响应)
//
// 架构:
//   读 DMA FSM: IDLE → RD_ADDR → RD_DATA → DONE
//   写 DMA FSM: IDLE → WR_ADDR → WR_DATA → WR_RESP → DONE
//
// 关键设计决策:
//   - 64-bit AXI 数据宽度: 4×Q8.8/beat, 平衡带宽与复杂度
//   - 最大 burst=16 (可配置): 减少地址握手开销
//   - 按 tile 地址生成 1D 地址: addr = base + row×stride + col×2
//   - 支持 BACKPRESSURE (AXI4 标准握手)
//
// 参考:
//   - 赛题要求: ../题目要求.md §2.1(5)
//   - 架构设计: ../docs/ARCHITECTURE.md §7
// ==========================================================================

`ifndef AXI4_DMA_ENGINE_SV
`define AXI4_DMA_ENGINE_SV

`timescale 1ns / 1ps

module axi4_dma_engine #(
    parameter int AXI_DATA_WIDTH  = 64,   // AXI4 数据位宽
    parameter int AXI_ADDR_WIDTH  = 64,   // AXI4 地址位宽
    parameter int AXI_ID_WIDTH    = 4,    // AXI4 ID 位宽
    parameter int MAX_BURST_LEN   = 16    // 最大 burst 长度
) (
    // ---- 时钟 & 复位 ----
    input  logic                         clk,
    input  logic                         rst_n,

    // ==================================================================
    // 控制接口 (来自顶层 FSM)
    // ==================================================================
    input  logic                         dma_start_rd,     // 启动读 DMA
    input  logic                         dma_start_wr,     // 启动写 DMA
    input  logic [AXI_ADDR_WIDTH-1:0]    dma_base_addr,    // 基地址
    input  logic [15:0]                  dma_tile_rows,    // Tile 行数
    input  logic [15:0]                  dma_tile_cols,    // Tile 列数
    input  logic [15:0]                  dma_row_stride,   // 行 stride (bytes)
    output logic                         dma_done,         // DMA 完成
    output logic                         dma_error,        // DMA 错误

    // ==================================================================
    // SRAM 接口 (读写 tile buffer)
    // ==================================================================
    output logic [15:0]                  sram_addr,        // SRAM 地址
    output logic                         sram_wr_en,       // SRAM 写使能
    output logic [AXI_DATA_WIDTH-1:0]    sram_wr_data,     // SRAM 写数据
    input  logic [AXI_DATA_WIDTH-1:0]    sram_rd_data,     // SRAM 读数据

    // ==================================================================
    // AXI4-Master 读地址通道 (AR)
    // ==================================================================
    output logic [AXI_ID_WIDTH-1:0]      m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0]    m_axi_araddr,
    output logic [7:0]                   m_axi_arlen,
    output logic [2:0]                   m_axi_arsize,
    output logic [1:0]                   m_axi_arburst,
    output logic                         m_axi_arvalid,
    input  logic                         m_axi_arready,

    // ==================================================================
    // AXI4-Master 读数据通道 (R)
    // ==================================================================
    input  logic [AXI_ID_WIDTH-1:0]      m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
    input  logic [1:0]                   m_axi_rresp,
    input  logic                         m_axi_rlast,
    input  logic                         m_axi_rvalid,
    output logic                         m_axi_rready,

    // ==================================================================
    // AXI4-Master 写地址通道 (AW)
    // ==================================================================
    output logic [AXI_ID_WIDTH-1:0]      m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0]    m_axi_awaddr,
    output logic [7:0]                   m_axi_awlen,
    output logic [2:0]                   m_axi_awsize,
    output logic [1:0]                   m_axi_awburst,
    output logic                         m_axi_awvalid,
    input  logic                         m_axi_awready,

    // ==================================================================
    // AXI4-Master 写数据通道 (W)
    // ==================================================================
    output logic [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
    output logic [AXI_DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output logic                         m_axi_wlast,
    output logic                         m_axi_wvalid,
    input  logic                         m_axi_wready,

    // ==================================================================
    // AXI4-Master 写响应通道 (B)
    // ==================================================================
    input  logic [AXI_ID_WIDTH-1:0]      m_axi_bid,
    input  logic [1:0]                   m_axi_bresp,
    input  logic                         m_axi_bvalid,
    output logic                         m_axi_bready
);

    // ======================================================================
    // DMA 读 FSM:
    //   IDLE → 收到 dma_start_rd → RD_ADDR → RD_DATA → DONE
    //   地址生成: addr = dma_base_addr + elem_cnt × 2 (每 Q8.8 = 2 bytes)
    // ======================================================================

    // ======================================================================
    // DMA 写 FSM:
    //   IDLE → 收到 dma_start_wr → WR_ADDR → WR_DATA → WR_RESP → DONE
    //   数据来源: sram_rd_data → m_axi_wdata
    // ======================================================================

    // ======================================================================
    // 错误处理
    // ======================================================================
    // AXI RRESP/BRESP 非 OKAY → dma_error = 1

endmodule

`endif // AXI4_DMA_ENGINE_SV
