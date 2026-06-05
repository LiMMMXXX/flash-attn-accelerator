// ==========================================================================
// test_flashattn_basic — 基础 UVM Test (寄存器读写)
// ==========================================================================
// 功能: 运行寄存器读写 Sequence, 验证 AXI4-Lite CSR 基本功能
//
// UVM 概念对照:
//   Test = uvm_test 的子类
//   在 run_phase 中启动 Sequence
//   raise_objection / drop_objection 控制仿真生命周期
//   -- 有 objection → 仿真继续
//   -- 无 objection → 仿真结束
// ==========================================================================

`ifndef TEST_FLASHATTN_BASIC_SV
`define TEST_FLASHATTN_BASIC_SV

class test_flashattn_basic extends uvm_test;

    `uvm_component_utils(test_flashattn_basic)

    flashattn_env    env;
    flashattn_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 创建配置
        cfg = flashattn_config::type_id::create("cfg");
        uvm_config_db#(flashattn_config)::set(this, "env", "cfg", cfg);

        // 创建环境
        env = flashattn_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        flashattn_reg_rw_seq seq;

        // raise_objection: "我还有工作没做完, 请继续仿真"
        phase.raise_objection(this);

        seq = flashattn_reg_rw_seq::type_id::create("seq");
        seq.start(env.axil_agt.sequencer);

        // drop_objection: "我完成了, 可以结束仿真了"
        phase.drop_objection(this);
    endtask

endclass

`endif // TEST_FLASHATTN_BASIC_SV
