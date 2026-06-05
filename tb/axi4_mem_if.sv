// ==========================================================================
// axi4_mem_if — AXI4-Master 接口定义 (用于模拟 DDR 内存)
// ==========================================================================
// UVM 验证环境中模拟外部 DDR: DUT 的 AXI4-Master 发出读写请求,
// 此接口连接到一个 Slave 模型, 响应读数据和接收写数据
// ==========================================================================

`ifndef AXI4_MEM_IF_SV
`define AXI4_MEM_IF_SV

`timescale 1ns / 1ps

interface axi4_mem_if #(
    parameter int ADDR_WIDTH = 64,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4
) (
    input logic clk,
    input logic rst_n
);
    // ---- 读地址通道 ----
    logic [ID_WIDTH-1:0]    arid;
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [7:0]             arlen;
    logic [2:0]             arsize;
    logic [1:0]             arburst;
    logic                   arvalid;
    logic                   arready;

    // ---- 读数据通道 ----
    logic [ID_WIDTH-1:0]    rid;
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rlast;
    logic                   rvalid;
    logic                   rready;

    // ---- 写地址通道 ----
    logic [ID_WIDTH-1:0]    awid;
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic [7:0]             awlen;
    logic [2:0]             awsize;
    logic [1:0]             awburst;
    logic                   awvalid;
    logic                   awready;

    // ---- 写数据通道 ----
    logic [DATA_WIDTH-1:0]  wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                   wlast;
    logic                   wvalid;
    logic                   wready;

    // ---- 写响应通道 ----
    logic [ID_WIDTH-1:0]    bid;
    logic [1:0]             bresp;
    logic                   bvalid;
    logic                   bready;

    // ==================================================================
    // Master modport (DUT 是 Master, 连接到此接口)
    // ==================================================================
    modport master (
        output arid, araddr, arlen, arsize, arburst, arvalid, input  arready,
        input  rid,  rdata,  rresp, rlast,  rvalid,  output rready,
        output awid, awaddr, awlen, awsize, awburst, awvalid, input  awready,
        output wdata, wstrb, wlast, wvalid, input  wready,
        input  bid,  bresp, bvalid, output bready
    );

    // ==================================================================
    // Slave modport (TB 的 DDR 模型, 接收 DUT 的 AXI4 请求)
    // ==================================================================
    modport slave (
        input  arid, araddr, arlen, arsize, arburst, arvalid, output arready,
        output rid,  rdata,  rresp, rlast,  rvalid,  input  rready,
        input  awid, awaddr, awlen, awsize, awburst, awvalid, output awready,
        input  wdata, wstrb, wlast, wvalid, output wready,
        output bid,  bresp, bvalid, input  bready
    );

    // ==================================================================
    // Monitor modport (被动观测)
    // ==================================================================
    modport monitor (
        input arid, araddr, arlen, arsize, arburst, arvalid, arready,
        input rid,  rdata,  rresp, rlast,  rvalid,  rready,
        input awid, awaddr, awlen, awsize, awburst, awvalid, awready,
        input wdata, wstrb, wlast, wvalid, wready,
        input bid,  bresp, bvalid, bready
    );

endinterface

`endif // AXI4_MEM_IF_SV
