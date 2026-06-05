// ==========================================================================
// axi4_mem_agent — AXI4 内存 Agent (UVM)
// ==========================================================================

`ifndef AXI4_MEM_AGENT_SV
`define AXI4_MEM_AGENT_SV

class axi4_mem_agent extends uvm_agent;

    `uvm_component_utils(axi4_mem_agent)

    axi4_mem_driver  driver;
    axi4_mem_monitor monitor;
    virtual axi4_mem_if vif;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_mem_if)::get(this, "", "axi4_vif", vif))
            `uvm_fatal("MEM_AGT", "Virtual interface not found")

        driver  = axi4_mem_driver::type_id::create("driver", this);
        monitor = axi4_mem_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        uvm_config_db#(virtual axi4_mem_if.slave)::set(this, "driver",
            "axi4_vif", vif.slave);
        uvm_config_db#(virtual axi4_mem_if.monitor)::set(this, "monitor",
            "axi4_vif", vif.monitor);
    endfunction

endclass

`endif // AXI4_MEM_AGENT_SV
