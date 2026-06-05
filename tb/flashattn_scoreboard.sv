// ==========================================================================
// flashattn_scoreboard — FlashAttention Scoreboard (UVM)
// ==========================================================================
// 功能: 接收 Monitor 捕获的 DUT 输出, 与 golden model 对比
//       - 从 AXI4 Monitor 获取 DMA 写回的数据 (O 矩阵)
//       - 调用 golden model (通过 DPI-C 调用 Python 或 SV 实现)
//       - 验证精度: mean_abs_error ≤ 0.03, max_abs_error ≤ 0.10
//
// UVM 概念对照:
//   Scoreboard = uvm_scoreboard 的子类
//   持有 analysis_imp (analysis import) 端口
//   analysis_imp.write(tx) → 当 Monitor 广播 Transaction 时自动调用
//   通常用 FIFO 缓冲 DUT 和 REF 的数据, 然后逐对比较
// ==========================================================================

`ifndef FLASHATTN_SCOREBOARD_SV
`define FLASHATTN_SCOREBOARD_SV

class flashattn_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(flashattn_scoreboard)

    // ---- Analysis Import: 接收来自 Monitor 的 O 输出数据 ----
    uvm_analysis_imp #(axi4_mem_trans, flashattn_scoreboard) o_data_imp;

    // ---- 参考数据 ----
    // 存储 golden model 的输出 (由 test 在启动 DUT 前写入)
    bit [15:0] golden_o [][];  // golden O 矩阵 [256][64] Q8.8

    // ---- DUT 输出 ----
    bit [15:0] dut_o [][];     // DUT O 矩阵 [256][64] Q8.8
    bit        dut_o_received; // 是否收到 DUT 输出

    // ---- 配置 ----
    flashattn_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        o_data_imp = new("o_data_imp", this);
        if (!uvm_config_db#(flashattn_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("SCB", "Config not found")
    endfunction

    // ==================================================================
    // write: 当 Monitor 广播 Transaction 时自动调用
    // ==================================================================
    function void write(axi4_mem_trans tx);
        if (tx.kind == axi4_mem_trans::WRITE) begin
            // DUT 正在写回 O 数据到 DDR
            `uvm_info("SCB", "DUT write detected — collecting O data", UVM_HIGH)
            // 从 DDR 模型读取 O 矩阵
            dut_o_received = 1'b1;
        end
    endfunction

    // ==================================================================
    // compare: 对比 DUT 和 Golden 输出
    // ==================================================================
    function void compare_results();
        real mean_err, max_err;
        real abs_err;
        int total = cfg.seq_len * cfg.head_dim;

        mean_err = 0.0;
        max_err  = 0.0;

        for (int r = 0; r < cfg.seq_len; r++) begin
            for (int c = 0; c < cfg.head_dim; c++) begin
                // Q8.8 → FP32
                real dut_val    = $itor($signed(dut_o[r][c])) / 256.0;
                real golden_val = $itor($signed(golden_o[r][c])) / 256.0;
                abs_err = dut_val - golden_val;
                if (abs_err < 0) abs_err = -abs_err;

                mean_err += abs_err;
                if (abs_err > max_err) max_err = abs_err;
            end
        end
        mean_err /= real'(total);

        `uvm_info("SCB", $sformatf("mean_abs_error = %.6f (limit: %.3f)",
                                   mean_err, cfg.max_mean_error), UVM_LOW)
        `uvm_info("SCB", $sformatf("max_abs_error  = %.6f (limit: %.3f)",
                                   max_err, cfg.max_max_error), UVM_LOW)

        if (mean_err > cfg.max_mean_error)
            `uvm_error("SCB", $sformatf("mean_abs_error %.4f exceeds limit", mean_err))
        else
            `uvm_info("SCB", "[PASS] mean_abs_error check", UVM_LOW)

        if (max_err > cfg.max_max_error)
            `uvm_error("SCB", $sformatf("max_abs_error %.4f exceeds limit", max_err))
        else
            `uvm_info("SCB", "[PASS] max_abs_error check", UVM_LOW)
    endfunction

endclass

`endif // FLASHATTN_SCOREBOARD_SV
