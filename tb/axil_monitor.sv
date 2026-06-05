// ==========================================================================
// axil_monitor — AXI4-Lite Monitor (UVM 组件)
// ==========================================================================
// 功能: 被动观测 AXI4-Lite 总线上的所有传输, 将捕获的 Transaction
//       通过 analysis_port 广播给 Scoreboard 和 Coverage Collector
//
// UVM 概念对照:
//   Monitor = uvm_monitor 的子类
//   不驱动任何信号, 只"监听"
//   通过 analysis_port.write(tx) 广播 Transaction
//   analysis_port 是一个广播通道 (1 对多)
//
// 为什么 Driver 和 Monitor 分开?
//   - Driver 负责"驱动" (主动), Monitor 负责"观测" (被动)
//   - 分开后可以在不同 agent 中重用 Monitor
//   - Scoreboard 通过 Monitor 拿到"实际发生了什么"
// ==========================================================================

`ifndef AXIL_MONITOR_SV
`define AXIL_MONITOR_SV

class axil_monitor extends uvm_monitor;

    `uvm_component_utils(axil_monitor)

    // ---- Virtual Interface (monitor modport — 只读) ----
    virtual axil_if.monitor vif;

    // ---- Analysis Port: 广播捕获到的 Transaction ----
    uvm_analysis_port #(axil_transfer) ap;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual axil_if.monitor)::get(this, "", "axil_vif", vif))
            `uvm_fatal("AXIL_MON", "Virtual interface not found in config_db")
    endfunction

    // ==================================================================
    // run_phase: 持续监控总线, 捕获所有传输
    // ==================================================================
    task run_phase(uvm_phase phase);
        axil_transfer tx;
        @(posedge vif.rst_n);

        forever begin
            @(posedge vif.clk);

            // 检测写事务: 写响应有效 → 一次写完成
            if (vif.bvalid && vif.bready) begin
                tx = axil_transfer::type_id::create("tx");
                tx.kind = axil_transfer::WRITE;
                tx.addr = '0;  // 地址已在 aw 阶段捕获 (简化实现)
                tx.data = '0;  // 数据已在 w 阶段捕获 (简化实现)
                tx.resp = vif.bresp;
                ap.write(tx);  // 广播!
            end

            // 检测读事务: 读数据有效且 ready
            if (vif.rvalid && vif.rready) begin
                tx = axil_transfer::type_id::create("tx");
                tx.kind = axil_transfer::READ;
                tx.data = vif.rdata;
                tx.resp = vif.rresp;
                ap.write(tx);  // 广播!
            end
        end
    endtask

endclass

`endif // AXIL_MONITOR_SV
