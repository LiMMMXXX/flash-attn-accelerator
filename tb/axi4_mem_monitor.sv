// ==========================================================================
// axi4_mem_monitor — AXI4 内存总线 Monitor (UVM 组件)
// ==========================================================================
// 功能: 被动观测 DUT 的 AXI4-Master 活动 (DMA 操作)
//       捕获每次 burst 传输, 广播给 Scoreboard
// ==========================================================================

`ifndef AXI4_MEM_MONITOR_SV
`define AXI4_MEM_MONITOR_SV

class axi4_mem_monitor extends uvm_monitor;

    `uvm_component_utils(axi4_mem_monitor)

    virtual axi4_mem_if.monitor vif;
    uvm_analysis_port #(axi4_mem_trans) ap;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual axi4_mem_if.monitor)::get(this, "", "axi4_vif", vif))
            `uvm_fatal("MEM_MON", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_reads();
            monitor_writes();
        join
    endtask

    task monitor_reads();
        forever begin
            @(posedge vif.clk);
            if (vif.arvalid && vif.arready) begin
                axi4_mem_trans tx = axi4_mem_trans::type_id::create("tx");
                tx.kind = axi4_mem_trans::READ;
                tx.addr = vif.araddr;
                tx.burst_len = vif.arlen;
                tx.burst_size = vif.arsize;
                tx.data = new[tx.burst_len + 1];
                // 等数据回来
                for (int i = 0; i <= tx.burst_len; i++) begin
                    @(posedge vif.clk);
                    while (!(vif.rvalid && vif.rready)) @(posedge vif.clk);
                    tx.data[i] = vif.rdata;
                end
                ap.write(tx);
                `uvm_info("MEM_MON", tx.convert2string(), UVM_HIGH)
            end
        end
    endtask

    task monitor_writes();
        forever begin
            @(posedge vif.clk);
            if (vif.awvalid && vif.awready) begin
                axi4_mem_trans tx = axi4_mem_trans::type_id::create("tx");
                tx.kind = axi4_mem_trans::WRITE;
                tx.addr = vif.awaddr;
                tx.burst_len = vif.awlen;
                tx.burst_size = vif.awsize;
                tx.data = new[tx.burst_len + 1];
                for (int i = 0; i <= tx.burst_len; i++) begin
                    @(posedge vif.clk);
                    while (!(vif.wvalid && vif.wready)) @(posedge vif.clk);
                    tx.data[i] = vif.wdata;
                end
                ap.write(tx);
                `uvm_info("MEM_MON", tx.convert2string(), UVM_HIGH)
            end
        end
    endtask

endclass

`endif // AXI4_MEM_MONITOR_SV
