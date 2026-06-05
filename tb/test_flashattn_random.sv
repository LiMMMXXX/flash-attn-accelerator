// ==========================================================================
// test_flashattn_random — 随机注意力 UVM Test
// ==========================================================================

`ifndef TEST_FLASHATTN_RANDOM_SV
`define TEST_FLASHATTN_RANDOM_SV

class test_flashattn_random extends uvm_test;

    `uvm_component_utils(test_flashattn_random)

    flashattn_env    env;
    flashattn_config cfg;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg = flashattn_config::type_id::create("cfg");
        uvm_config_db#(flashattn_config)::set(this, "env", "cfg", cfg);
        env = flashattn_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        flashattn_rand_seq seq;
        phase.raise_objection(this);
        seq = flashattn_rand_seq::type_id::create("seq");
        seq.start(env.axil_agt.sequencer);
        phase.drop_objection(this);
    endtask

endclass

`endif // TEST_FLASHATTN_RANDOM_SV
