// ==========================================================================
// test_flashattn_complete — 完整 UVM Test (全部 3 个必须项)
// ==========================================================================

`ifndef TEST_FLASHATTN_COMPLETE_SV
`define TEST_FLASHATTN_COMPLETE_SV

class test_flashattn_complete extends uvm_test;

    `uvm_component_utils(test_flashattn_complete)

    flashattn_env    env;
    flashattn_config cfg;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg = flashattn_config::type_id::create("cfg");
        uvm_config_db#(flashattn_config)::set(this, "env", "cfg", cfg);
        env = flashattn_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        // ---- Test 1: 寄存器读写 ----
        begin
            flashattn_reg_rw_seq seq1;
            `uvm_info("COMPLETE", ">>> T1: Register R/W Test <<<", UVM_LOW)
            seq1 = flashattn_reg_rw_seq::type_id::create("seq1");
            seq1.start(env.axil_agt.sequencer);
        end

        // ---- Test 2: 随机端到端 (多轮) ----
        begin
            flashattn_rand_seq seq2;
            `uvm_info("COMPLETE", ">>> T2: Random End-to-End Test <<<", UVM_LOW)
            // 运行多轮随机测试
            for (int seed = 0; seed < cfg.num_random_tests; seed++) begin
                `uvm_info("COMPLETE", $sformatf("Round %0d/%0d (seed=%0d)",
                    seed+1, cfg.num_random_tests, seed), UVM_MEDIUM)
                seq2 = flashattn_rand_seq::type_id::create("seq2");
                seq2.start(env.axil_agt.sequencer);
            end
        end

        // ---- Test 3: Causal mask corner case ----
        begin
            flashattn_causal_corner_seq seq3;
            `uvm_info("COMPLETE", ">>> T3: Causal Mask Corner Case <<<", UVM_LOW)
            seq3 = flashattn_causal_corner_seq::type_id::create("seq3");
            seq3.start(env.axil_agt.sequencer);
        end

        phase.drop_objection(this);
    endtask

endclass

`endif // TEST_FLASHATTN_COMPLETE_SV
