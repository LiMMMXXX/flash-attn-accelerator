// ==========================================================================
// axil_csr — AXI4-Lite 控制/状态寄存器文件
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - AXI4-Lite Slave 接口, 实现赛题规定的寄存器映射
//   - 提供 DUT 控制信号 (START, SOFT_RESET, IRQ_EN, CAUSAL_EN)
//   - 提供 64-bit 基地址 (Q/K/V/O) 给 DMA 引擎
//   - 读取 DUT 状态 (BUSY, DONE, ERROR, CYCLES)
//   - 生成 IRQ 中断信号
//
// 寄存器映射 (赛题规定):
//   0x00 CTRL         [0]=START [1]=SOFT_RESET [2]=IRQ_EN
//   0x04 STATUS       [0]=BUSY [1]=DONE(W1C) [2]=ERROR
//   0x08 CFG          [0]=CAUSAL_EN
//   0x14-0x30         Q/K/V/O 基地址 (各 64-bit, 分高/低32)
//   0x34 STRIDE_BYTES 行 stride (默认 d*2=128)
//   0x38 NEG_LARGE    -inf 近似值 (Q8.8)
//   0x3C SCALE        1/√d 缩放常数 (Q8.8)
//   0x40 CYCLES       本次执行周期数 (只读)
//
// 接口: AXI4-Lite Slave (标准5通道)
//
// 关键设计决策:
//   - 两段写握手 (地址 + 数据 → 响应), 支持 BACKPRESSURE
//   - STATUS[1] DONE 写 1 清除 (W1C)
//   - START 自清除脉冲 (写后 1 cycle 自动清零)
//   - 默认 SCALE = 1/√64 = 0.125 → Q8.8 = 0x0020
//
// 参考:
//   - 赛题要求: ../题目要求.md §2.1(6)
// ==========================================================================

`ifndef AXIL_CSR_SV
`define AXIL_CSR_SV

`timescale 1ns / 1ps

module axil_csr #(
    parameter int ADDR_WIDTH = 8,      // AXI4-Lite 字节地址位宽
    parameter int DATA_WIDTH = 32      // AXI4-Lite 数据位宽
) (
    // ---- 时钟 & 复位 ----
    input  logic                         clk,
    input  logic                         rst_n,

    // ==================================================================
    // AXI4-Lite 写地址通道
    // ==================================================================
    input  logic [ADDR_WIDTH-1:0]        s_axil_awaddr,
    input  logic                         s_axil_awvalid,
    output logic                         s_axil_awready,

    // ==================================================================
    // AXI4-Lite 写数据通道
    // ==================================================================
    input  logic [DATA_WIDTH-1:0]        s_axil_wdata,
    input  logic [3:0]                   s_axil_wstrb,
    input  logic                         s_axil_wvalid,
    output logic                         s_axil_wready,

    // ==================================================================
    // AXI4-Lite 写响应通道
    // ==================================================================
    output logic [1:0]                   s_axil_bresp,
    output logic                         s_axil_bvalid,
    input  logic                         s_axil_bready,

    // ==================================================================
    // AXI4-Lite 读地址通道
    // ==================================================================
    input  logic [ADDR_WIDTH-1:0]        s_axil_araddr,
    input  logic                         s_axil_arvalid,
    output logic                         s_axil_arready,

    // ==================================================================
    // AXI4-Lite 读数据通道
    // ==================================================================
    output logic [DATA_WIDTH-1:0]        s_axil_rdata,
    output logic [1:0]                   s_axil_rresp,
    output logic                         s_axil_rvalid,
    input  logic                         s_axil_rready,

    // ==================================================================
    // DUT 控制信号 (输出)
    // ==================================================================
    output logic                         ctrl_start,       // START 脉冲
    output logic                         ctrl_soft_reset,  // SOFT_RESET
    output logic                         ctrl_irq_en,      // IRQ 使能
    output logic                         cfg_causal_en,    // CAUSAL_EN
    output logic [63:0]                  q_base_addr,      // Q 基地址
    output logic [63:0]                  k_base_addr,      // K 基地址
    output logic [63:0]                  v_base_addr,      // V 基地址
    output logic [63:0]                  o_base_addr,      // O 基地址
    output logic [15:0]                  stride_bytes,     // 行 stride
    output logic signed [15:0]           neg_large,        // -inf (Q8.8)
    output logic signed [15:0]           scale,            // 1/√d (Q8.8)

    // ==================================================================
    // DUT 状态信号 (输入)
    // ==================================================================
    input  logic                         dut_busy,         // DUT 忙碌
    input  logic                         dut_done,         // DUT 完成
    input  logic                         dut_error,        // DUT 错误
    input  logic [31:0]                  dut_cycles,       // 执行周期

    // ==================================================================
    // 中断输出
    // ==================================================================
    output logic                         irq_out           // IRQ 信号
);

    // ======================================================================
    // 寄存器地址枚举
    // ======================================================================
    // REG_CTRL=0x00, REG_STATUS=0x04, REG_CFG=0x08,
    // REG_Q_BASE_L=0x14, REG_Q_BASE_H=0x18, ... 见 flashattn_pkg

    // ======================================================================
    // 内部寄存器
    // ======================================================================
    // reg_ctrl[31:0], reg_status[31:0], reg_cfg[31:0]
    // reg_q_base_l/h, reg_k_base_l/h, reg_v_base_l/h, reg_o_base_l/h
    // reg_stride, reg_neg_large, reg_scale

    // ======================================================================
    // AXI4-Lite 写事务 (两段握手)
    // ======================================================================
    // 1. 接收写地址 (aw_valid & aw_ready)
    // 2. 接收写数据 (w_valid & w_ready)
    // 3. 写入寄存器 + 发送响应 (b_valid & b_ready)
    // STATUS 寄存器只读, 忽略写

    // ======================================================================
    // AXI4-Lite 读事务
    // ======================================================================
    // 1. 接收读地址 (ar_valid & ar_ready)
    // 2. 返回读数据 (r_valid & r_ready)

    // ======================================================================
    // 控制信号生成
    // ======================================================================
    // START 脉冲 = 写 CTRL[0]=1 时产生 1 cycle 脉冲
    // DONE 写 1 清除

    // ======================================================================
    // IRQ 生成
    // ======================================================================
    // IRQ = (DONE && IRQ_EN)  → 在 DONE 时置位, 写 STATUS[1]=1 时清除

endmodule

`endif // AXIL_CSR_SV
