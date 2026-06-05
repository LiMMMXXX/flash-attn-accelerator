// ==========================================================================
// test_top — FlashAttention UVM 测试顶层 (Top-Level Testbench)
// ==========================================================================
// 功能:
//   - 实例化 DUT (flashattn_top)
//   - 创建 clock + reset
//   - 实例化 interface (axil_if, axi4_mem_if)
//   - 将 interface 通过 config_db 传递给 UVM 环境
//   - 调用 run_test() 启动 UVM
//
// 这是非 UVM 的顶层 module, 负责硬件与 UVM 之间的桥梁
// ==========================================================================

`ifndef TEST_TOP_SV
`define TEST_TOP_SV

`timescale 1ns / 1ps

// ======================================================================
// 导入 UVM 和验证包
// ======================================================================
import uvm_pkg::*;

// 所有 UVM 组件在 flashattn_tb_pkg 中
// `include "flashattn_tb_pkg.sv"  (在编译脚本中 include)

module test_top;

    // ==================================================================
    // Clock & Reset
    // ==================================================================
    logic clk;
    logic rst_n;

    // 500 MHz clock (2 ns period)
    initial clk = 0;
    always #1000 clk = ~clk;  // 1000 ps = 1 ns → 2 ns period

    // 初始复位
    initial begin
        rst_n = 0;
        #5000;       // 等待 5 ns
        rst_n = 1;
        #2000;       // 等待 2 ns 后复位释放
    end

    // ==================================================================
    // Interfaces 实例化
    // ==================================================================
    axil_if #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) axil_vif (.clk(clk), .rst_n(rst_n));
    axi4_mem_if #(.ADDR_WIDTH(64), .DATA_WIDTH(64), .ID_WIDTH(4))
        mem_vif (.clk(clk), .rst_n(rst_n));

    // ==================================================================
    // DUT 实例化 (flashattn_top)
    // ==================================================================
    flashattn_top #(
        .S(256), .D(64), .BR(64), .BC(64),
        .AXI_ADDR_W(64), .AXI_DATA_W(64), .AXI_ID_W(4)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        // AXI4-Lite
        .s_axil_awaddr    (axil_vif.slave.awaddr),
        .s_axil_awvalid   (axil_vif.slave.awvalid),
        .s_axil_awready   (axil_vif.slave.awready),
        .s_axil_wdata     (axil_vif.slave.wdata),
        .s_axil_wstrb     (axil_vif.slave.wstrb),
        .s_axil_wvalid    (axil_vif.slave.wvalid),
        .s_axil_wready    (axil_vif.slave.wready),
        .s_axil_bresp     (axil_vif.slave.bresp),
        .s_axil_bvalid    (axil_vif.slave.bvalid),
        .s_axil_bready    (axil_vif.slave.bready),
        .s_axil_araddr    (axil_vif.slave.araddr),
        .s_axil_arvalid   (axil_vif.slave.arvalid),
        .s_axil_arready   (axil_vif.slave.arready),
        .s_axil_rdata     (axil_vif.slave.rdata),
        .s_axil_rresp     (axil_vif.slave.rresp),
        .s_axil_rvalid    (axil_vif.slave.rvalid),
        .s_axil_rready    (axil_vif.slave.rready),
        // AXI4-Master (连接 DDR 模拟)
        .m_axi_arid       (mem_vif.master.arid),
        .m_axi_araddr     (mem_vif.master.araddr),
        .m_axi_arlen      (mem_vif.master.arlen),
        .m_axi_arsize     (mem_vif.master.arsize),
        .m_axi_arburst    (mem_vif.master.arburst),
        .m_axi_arvalid    (mem_vif.master.arvalid),
        .m_axi_arready    (mem_vif.master.arready),
        .m_axi_rid        (mem_vif.master.rid),
        .m_axi_rdata      (mem_vif.master.rdata),
        .m_axi_rresp      (mem_vif.master.rresp),
        .m_axi_rlast      (mem_vif.master.rlast),
        .m_axi_rvalid     (mem_vif.master.rvalid),
        .m_axi_rready     (mem_vif.master.rready),
        .m_axi_awid       (mem_vif.master.awid),
        .m_axi_awaddr     (mem_vif.master.awaddr),
        .m_axi_awlen      (mem_vif.master.awlen),
        .m_axi_awsize     (mem_vif.master.awsize),
        .m_axi_awburst    (mem_vif.master.awburst),
        .m_axi_awvalid    (mem_vif.master.awvalid),
        .m_axi_awready    (mem_vif.master.awready),
        .m_axi_wdata      (mem_vif.master.wdata),
        .m_axi_wstrb      (mem_vif.master.wstrb),
        .m_axi_wlast      (mem_vif.master.wlast),
        .m_axi_wvalid     (mem_vif.master.wvalid),
        .m_axi_wready     (mem_vif.master.wready),
        .m_axi_bid        (mem_vif.master.bid),
        .m_axi_bresp      (mem_vif.master.bresp),
        .m_axi_bvalid     (mem_vif.master.bvalid),
        .m_axi_bready     (mem_vif.master.bready),
        // 中断
        .irq_out          (irq_out)
    );

    logic irq_out;

    // ==================================================================
    // UVM 启动
    // ==================================================================
    initial begin
        // 将 virtual interfaces 注册到 config_db
        uvm_config_db#(virtual axil_if)::set(null, "*", "axil_vif", axil_vif);
        uvm_config_db#(virtual axi4_mem_if)::set(null, "*", "mem_vif", mem_vif);

        // 启动 UVM
        // 命令行: +UVM_TESTNAME=test_flashattn_complete
        run_test();
    end

    // ==================================================================
    // 波形生成 (Xcelium: probe -create -all)
    // ==================================================================
    `ifdef DUMP_VCD
    initial begin
        $dumpfile("flashattn_tb.vcd");
        $dumpvars(0, test_top);
    end
    `endif

endmodule

`endif // TEST_TOP_SV
