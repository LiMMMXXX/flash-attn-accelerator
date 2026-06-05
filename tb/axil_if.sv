// ==========================================================================
// axil_if — AXI4-Lite 接口定义 (Interface)
// ==========================================================================
// UVM 验证环境中用于连接 Driver/Monitor 和 DUT 的虚拟接口
// ==========================================================================

`ifndef AXIL_IF_SV
`define AXIL_IF_SV

`timescale 1ns / 1ps

interface axil_if #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);
    // ---- 写地址通道 ----
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic                   awvalid;
    logic                   awready;

    // ---- 写数据通道 ----
    logic [DATA_WIDTH-1:0]  wdata;
    logic [3:0]             wstrb;
    logic                   wvalid;
    logic                   wready;

    // ---- 写响应通道 ----
    logic [1:0]             bresp;
    logic                   bvalid;
    logic                   bready;

    // ---- 读地址通道 ----
    logic [ADDR_WIDTH-1:0]  araddr;
    logic                   arvalid;
    logic                   arready;

    // ---- 读数据通道 ----
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rvalid;
    logic                   rready;

    // ==================================================================
    // Master modport (DUT 视角 — DUT 是 Slave, TB 是 Master)
    // ==================================================================
    modport master (
        output awaddr, awvalid, input  awready,
        output wdata,  wstrb,   wvalid, input  wready,
        input  bresp,  bvalid,  output bready,
        output araddr, arvalid, input  arready,
        input  rdata,  rresp,   rvalid, output rready
    );

    // ==================================================================
    // Slave modport (TB 模拟的 DUT Slave — 实际连接到 flashattn_top)
    // ==================================================================
    modport slave (
        input  awaddr, awvalid, output awready,
        input  wdata,  wstrb,   wvalid, output wready,
        output bresp,  bvalid,  input  bready,
        input  araddr, arvalid, output arready,
        output rdata,  rresp,   rvalid, input  rready
    );

    // ==================================================================
    // Monitor modport (被动观测, 不驱动任何信号)
    // ==================================================================
    modport monitor (
        input awaddr, awvalid, awready,
        input wdata,  wstrb,   wvalid, wready,
        input bresp,  bvalid,  bready,
        input araddr, arvalid, arready,
        input rdata,  rresp,   rvalid, rready
    );

endinterface

`endif // AXIL_IF_SV
