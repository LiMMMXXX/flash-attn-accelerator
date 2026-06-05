// ==========================================================================
// axil_agent — AXI4-Lite Agent (UVM 组件)
// ==========================================================================
// 功能: 封装 Driver + Sequencer + Monitor 成一个整体
//       配置为 Active (有 Driver/Sequencer) 或 Passive (仅 Monitor)
//
// UVM 概念对照:
//   Agent = uvm_agent 的子类
//   将相关组件打包: "这个接口的 Agent 包含一切"
//   Active:   可发起事务 (有 Driver + Sequencer)
//   Passive:  仅观测 (只有 Monitor)
//   通过 is_active 控制 (从 config_db 读取)
// ==========================================================================

`ifndef AXIL_AGENT_SV
`define AXIL_AGENT_SV

class axil_agent extends uvm_agent;

    `uvm_component_utils(axil_agent)

    // ---- 子组件 ----
    axil_driver     driver;
    axil_sequencer  sequencer;
    axil_monitor    monitor;

    // ---- Virtual Interface ----
    virtual axil_if vif;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 从 config_db 获取 virtual interface
        if (!uvm_config_db#(virtual axil_if)::get(this, "", "axil_vif", vif))
            `uvm_fatal("AXIL_AGT", "Virtual interface not found")

        // Monitor 总是创建 (无论 active/passive)
        monitor = axil_monitor::type_id::create("monitor", this);

        // 只在 Active 模式下创建 Driver 和 Sequencer
        if (get_is_active()) begin
            driver    = axil_driver::type_id::create("driver", this);
            sequencer = axil_sequencer::type_id::create("sequencer", this);
        end
    endfunction

    // ==================================================================
    // connect_phase: 连接组件
    //   Driver ↔ Sequencer 的 TLM 端口自动连接
    //   把 virtual interface 分成 master 和 monitor 分别传递
    // ==================================================================
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active()) begin
            // Driver 用 master modport (可驱动信号)
            uvm_config_db#(virtual axil_if.master)::set(this, "driver",
                "axil_vif", vif.master);
            // Driver → Sequencer TLM 连接 (seq_item_port ↔ seq_item_export)
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
        // Monitor 用 monitor modport (只读)
        uvm_config_db#(virtual axil_if.monitor)::set(this, "monitor",
            "axil_vif", vif.monitor);
    endfunction

endclass

`endif // AXIL_AGENT_SV
