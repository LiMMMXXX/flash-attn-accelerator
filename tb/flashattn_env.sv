// ==========================================================================
// flashattn_env — FlashAttention 验证环境 (UVM Env)
// ==========================================================================
// 功能: 实例化所有 Agent, Scoreboard, Coverage Collector
//       通过 config_db 传递 virtual interface 和配置
//
// UVM 概念对照:
//   Env = uvm_env 的子类
//   层次结构: Test → Env → Agent → Driver/Monitor/Sequencer
//   Env 负责"组装"所有组件
//   config_db 在 build_phase 中设置 → 子组件在 build_phase 中 get
// ==========================================================================

`ifndef FLASHATTN_ENV_SV
`define FLASHATTN_ENV_SV

class flashattn_env extends uvm_env;

    `uvm_component_utils(flashattn_env)

    // ---- 子组件 ----
    axil_agent              axil_agt;       // AXI4-Lite Agent (active)
    axi4_mem_agent          mem_agt;        // AXI4 Slave 内存 Agent
    // TODO: scoreboard 和 coverage 稍后添加
    // flashattn_scoreboard  scoreboard;
    // flashattn_coverage    coverage;

    // ---- 配置 ----
    flashattn_config        cfg;

    // ---- Virtual Interfaces ----
    virtual axil_if         axil_vif;
    virtual axi4_mem_if     mem_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // ---- 获取配置 ----
        if (!uvm_config_db#(flashattn_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("ENV", "Config not found in config_db")

        // ---- 获取 virtual interfaces ----
        if (!uvm_config_db#(virtual axil_if)::get(this, "", "axil_vif", axil_vif))
            `uvm_fatal("ENV", "axil_vif not found")
        if (!uvm_config_db#(virtual axi4_mem_if)::get(this, "", "mem_vif", mem_vif))
            `uvm_fatal("ENV", "mem_vif not found")

        // ---- 创建 Agent ----
        axil_agt = axil_agent::type_id::create("axil_agt", this);
        uvm_config_db#(virtual axil_if)::set(this, "axil_agt", "axil_vif", axil_vif);
        uvm_config_db#(int)::set(this, "axil_agt", "is_active", UVM_ACTIVE);

        mem_agt = axi4_mem_agent::type_id::create("mem_agt", this);
        uvm_config_db#(virtual axi4_mem_if)::set(this, "mem_agt", "axi4_vif", mem_vif);

        // TODO: scoreboard, coverage
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // TODO: Monitor ap → Scoreboard ap.connect()
    endfunction

endclass

`endif // FLASHATTN_ENV_SV
