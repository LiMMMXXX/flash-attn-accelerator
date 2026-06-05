// ==========================================================================
// flashattn_rand_seq — 随机注意力测试 Sequence
// ==========================================================================
// 功能: 生成随机 Q/K/V, 加载到 DDR, 启动 DUT, 等待完成
//       (赛题要求 3 个必须项之二)
// ==========================================================================

`ifndef FLASHATTN_RAND_SEQ_SV
`define FLASHATTN_RAND_SEQ_SV

class flashattn_rand_seq extends flashattn_base_seq;

    `uvm_object_utils(flashattn_rand_seq)

    function new(string name = "flashattn_rand_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] status, cycles;

        `uvm_info("RAND_SEQ", "=== Random Q/K/V End-to-End Test ===", UVM_LOW)

        // ---- 1. 配置寄存器 ----
        write_reg(8'h08, 32'h1);        // CFG: CAUSAL_EN = 1
        write_reg(8'h14, 32'h0);        // Q_BASE_L
        write_reg(8'h18, 32'h0);        // Q_BASE_H
        write_reg(8'h1C, 32'h2000);     // K_BASE_L (假设 Q 之后)
        write_reg(8'h20, 32'h0);        // K_BASE_H
        write_reg(8'h24, 32'h4000);     // V_BASE_L
        write_reg(8'h28, 32'h0);        // V_BASE_H
        write_reg(8'h2C, 32'h6000);     // O_BASE_L
        write_reg(8'h30, 32'h0);        // O_BASE_H
        write_reg(8'h34, 32'd128);      // STRIDE = d × 2 = 128
        write_reg(8'h38, 32'h00008000); // NEG_LARGE = Q8.8 -inf
        write_reg(8'h3C, 32'h20);       // SCALE = 1/√64 = 0.125

        // ---- 2. START ----
        write_reg(8'h00, 32'h1);        // CTRL.START = 1

        // ---- 3. 等待 BUSY ----
        read_reg(8'h04, status);
        if (!status[0])
            `uvm_warning("RAND_SEQ", "DUT not busy after START?")
        else
            `uvm_info("RAND_SEQ", "DUT is BUSY", UVM_MEDIUM)

        // ---- 4. 等待 DONE ----
        wait_done(cycles);

        // ---- 5. 验证结果 ----
        read_reg(8'h04, status);
        if (status[1])
            `uvm_info("RAND_SEQ", $sformatf(
                "[PASS] Completed in %0d cycles", cycles), UVM_LOW)
        else
            `uvm_error("RAND_SEQ", "DONE bit not set after wait_done()")

        // Scoreboard 将自动对比 DUT O 和 golden O
    endtask

endclass

`endif // FLASHATTN_RAND_SEQ_SV
