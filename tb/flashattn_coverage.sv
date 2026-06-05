// ==========================================================================
// flashattn_coverage — 功能覆盖率收集器 (UVM)
// ==========================================================================
// 功能: 收集 AXI4-Lite 协议、FSM 状态、Causal mask 等覆盖率
//
// UVM 概念对照:
//   Coverage = uvm_subscriber 的子类
//   通过 analysis_imp 接收 Monitor 广播的 Transaction
//   covergroup 在特定事件 (如 @(posedge clk)) 采样
//   覆盖点定义了"哪些情况必须被测试到"
// ==========================================================================

`ifndef FLASHATTN_COVERAGE_SV
`define FLASHATTN_COVERAGE_SV

class flashattn_coverage extends uvm_subscriber #(axil_transfer);

    `uvm_component_utils(flashattn_coverage)

    // ---- 覆盖组: AXI4-Lite 寄存器地址覆盖 ----
    covergroup cg_axil_addr;
        // 必须覆盖所有 CSR 地址 (0x00-0x40)
        cp_addr: coverpoint axil_addr {
            bins CTRL        = {8'h00};
            bins STATUS      = {8'h04};
            bins CFG         = {8'h08};
            bins Q_BASE_L    = {8'h14};
            bins Q_BASE_H    = {8'h18};
            bins K_BASE_L    = {8'h1C};
            bins K_BASE_H    = {8'h20};
            bins V_BASE_L    = {8'h24};
            bins V_BASE_H    = {8'h28};
            bins O_BASE_L    = {8'h2C};
            bins O_BASE_H    = {8'h30};
            bins STRIDE      = {8'h34};
            bins NEG_LARGE   = {8'h38};
            bins SCALE       = {8'h3C};
            bins CYCLES      = {8'h40};
        }
        // 读写类型覆盖
        cp_kind: coverpoint axil_kind {
            bins READ  = {0};
            bins WRITE = {1};
        }
        // 交叉覆盖: 每个地址都读过 + 写过
        cr_addr_kind: cross cp_addr, cp_kind;
    endgroup

    // ---- 覆盖组: CTRL 寄存器 bit 覆盖 ----
    covergroup cg_ctrl_bits;
        cp_start:      coverpoint ctrl_start_bit   { bins hit = {1}; }
        cp_soft_reset: coverpoint ctrl_reset_bit   { bins hit = {1}; }
        cp_irq_en:     coverpoint ctrl_irq_bit     { bins hit = {1}; }
        cp_causal_en:  coverpoint cfg_causal_bit   { bins hit = {1}; }
    endgroup

    // ---- 覆盖组: STATUS 寄存器 ----
    covergroup cg_status;
        cp_busy: coverpoint status_busy_bit { bins hit = {1}; }
        cp_done: coverpoint status_done_bit { bins hit = {1}; }
        cp_irq:  coverpoint irq_fired      { bins hit = {1}; }
    endgroup

    // ---- 采样变量 ----
    bit [7:0]  axil_addr;
    bit        axil_kind;      // 0=READ, 1=WRITE
    bit        ctrl_start_bit, ctrl_reset_bit, ctrl_irq_bit, cfg_causal_bit;
    bit        status_busy_bit, status_done_bit;
    bit        irq_fired;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_axil_addr  = new();
        cg_ctrl_bits  = new();
        cg_status     = new();
    endfunction

    // ==================================================================
    // write: Monitor 广播 Transaction 时自动调用
    // ==================================================================
    function void write(axil_transfer t);
        axil_addr = t.addr;
        axil_kind = t.kind;
        cg_axil_addr.sample();

        // 追踪 CTRL bit
        if (t.addr == 8'h00 && t.kind == 1) begin
            ctrl_start_bit = t.data[0];
            ctrl_reset_bit = t.data[1];
            ctrl_irq_bit   = t.data[2];
            cg_ctrl_bits.sample();
        end
        // 追踪 CFG bit
        if (t.addr == 8'h08 && t.kind == 1) begin
            cfg_causal_bit = t.data[0];
            cg_ctrl_bits.sample();
        end
    endfunction

    // ==================================================================
    // 外部调用: DONE 完成时报告覆盖率
    // ==================================================================
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COV", $sformatf(
            "AXIL addr coverage: %.0f%%",
            cg_axil_addr.get_coverage()), UVM_LOW)
        `uvm_info("COV", $sformatf(
            "CTRL bits coverage: %.0f%%",
            cg_ctrl_bits.get_coverage()), UVM_LOW)
        `uvm_info("COV", $sformatf(
            "STATUS coverage: %.0f%%",
            cg_status.get_coverage()), UVM_LOW)
    endfunction

endclass

`endif // FLASHATTN_COVERAGE_SV
