// ==========================================================================
// axil_driver — AXI4-Lite Driver (UVM 组件)
// ==========================================================================
// 功能: 从 Sequencer 获取 Transaction, 驱动到 AXI4-Lite 接口上
//
// UVM 概念对照:
//   Driver = uvm_driver 的子类
//   持有 virtual interface (实际硬件信号)
//   seq_item_port.get_next_item(req)  → 从 Sequencer 拿一个 Transaction
//   驱动完成后 → seq_item_port.item_done()  → 告诉 Sequencer "完成"
//
// 数据流:
//   Sequence (产生Transaction) → Sequencer (排队) → Driver (驱动到DUT引脚)
// ==========================================================================

`ifndef AXIL_DRIVER_SV
`define AXIL_DRIVER_SV

class axil_driver extends uvm_driver #(axil_transfer);

    // 注册到 UVM factory
    `uvm_component_utils(axil_driver)

    // ---- Virtual Interface (连接到实际 DUT 信号) ----
    virtual axil_if.master vif;

    // ==================================================================
    // build_phase: 从 config_db 获取 virtual interface
    // ==================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axil_if.master)::get(this, "", "axil_vif", vif))
            `uvm_fatal("AXIL_DRV", "Virtual interface not found in config_db")
    endfunction

    // ==================================================================
    // run_phase: 持续从 Sequencer 获取 Transaction 并驱动
    // ==================================================================
    task run_phase(uvm_phase phase);
        // 复位时保持信号默认值
        vif.awaddr   <= '0;
        vif.awvalid  <= 1'b0;
        vif.wdata    <= '0;
        vif.wstrb    <= 4'h0;
        vif.wvalid   <= 1'b0;
        vif.bready   <= 1'b0;
        vif.araddr   <= '0;
        vif.arvalid  <= 1'b0;
        vif.rready   <= 1'b0;

        // 等待复位释放
        @(posedge vif.rst_n);

        // 主循环: 永远运行
        forever begin
            axil_transfer req;
            // 阻塞等待, 直到 Sequencer 有新的 Transaction
            seq_item_port.get_next_item(req);

            // 根据 Transaction 类型驱动接口
            if (req.kind == axil_transfer::WRITE)
                do_write(req);
            else
                do_read(req);

            // 告诉 Sequencer: 这个 Transaction 处理完毕
            seq_item_port.item_done();
        end
    endtask

    // ==================================================================
    // AXI4-Lite 写操作
    // ==================================================================
    task do_write(axil_transfer req);
        // ---- 写地址阶段 ----
        vif.awaddr  <= req.addr;
        vif.awvalid <= 1'b1;
        @(posedge vif.clk);
        while (!vif.awready) @(posedge vif.clk);
        vif.awvalid <= 1'b0;

        // ---- 写数据阶段 ----
        vif.wdata  <= req.data;
        vif.wstrb  <= 4'hF;    // 全字节有效
        vif.wvalid <= 1'b1;
        @(posedge vif.clk);
        while (!vif.wready) @(posedge vif.clk);
        vif.wvalid <= 1'b0;

        // ---- 写响应阶段 ----
        vif.bready <= 1'b1;
        @(posedge vif.clk);
        while (!vif.bvalid) @(posedge vif.clk);
        req.resp = vif.bresp;
        vif.bready <= 1'b0;

        `uvm_info("AXIL_DRV", $sformatf("WRITE: addr=0x%02h data=0x%08h resp=%0d",
                                        req.addr, req.data, req.resp), UVM_MEDIUM)
    endtask

    // ==================================================================
    // AXI4-Lite 读操作
    // ==================================================================
    task do_read(axil_transfer req);
        // ---- 读地址阶段 ----
        vif.araddr  <= req.addr;
        vif.arvalid <= 1'b1;
        @(posedge vif.clk);
        while (!vif.arready) @(posedge vif.clk);
        vif.arvalid <= 1'b0;

        // ---- 读数据阶段 ----
        vif.rready <= 1'b1;
        @(posedge vif.clk);
        while (!vif.rvalid) @(posedge vif.clk);
        req.data = vif.rdata;
        req.resp = vif.rresp;
        vif.rready <= 1'b0;

        `uvm_info("AXIL_DRV", $sformatf("READ:  addr=0x%02h data=0x%08h resp=%0d",
                                        req.addr, req.data, req.resp), UVM_MEDIUM)
    endtask

endclass

`endif // AXIL_DRIVER_SV
