// ==========================================================================
// flashattn_causal_corner_seq — Causal Mask 边界测试 Sequence
// ==========================================================================
// 功能: 验证 causal mask 的 corner case
//       (赛题要求 3 个必须项之三)
//       - i=0 行只能看到 j=0 (第一个 token 只能看到自己)
//       - i=255 行可以看到所有 j (最后一个 token 无遮挡)
// ==========================================================================

`ifndef FLASHATTN_CAUSAL_CORNER_SEQ_SV
`define FLASHATTN_CAUSAL_CORNER_SEQ_SV

class flashattn_causal_corner_seq extends flashattn_base_seq;

    `uvm_object_utils(flashattn_causal_corner_seq)

    function new(string name = "flashattn_causal_corner_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] status, cycles;

        `uvm_info("CAUSAL_SEQ", "=== Causal Mask Corner Case Test ===", UVM_LOW)

        // ---- 1. 启用 causal mask ----
        write_reg(8'h08, 32'h1);  // CFG: CAUSAL_EN = 1

        // ---- 2. 配置地址 ----
        write_reg(8'h14, 32'h0);        // Q_BASE
        write_reg(8'h1C, 32'h2000);     // K_BASE
        write_reg(8'h24, 32'h4000);     // V_BASE
        write_reg(8'h2C, 32'h6000);     // O_BASE
        write_reg(8'h34, 32'd128);      // STRIDE
        write_reg(8'h38, 32'h00008000); // NEG_LARGE
        write_reg(8'h3C, 32'h20);       // SCALE

        // ---- 3. START ----
        write_reg(8'h00, 32'h1);

        // ---- 4. 等待 DONE ----
        wait_done(cycles);
        `uvm_info("CAUSAL_SEQ", $sformatf("Completed in %0d cycles", cycles), UVM_LOW)

        // ---- 5. 验证: Scoreboard 检查 O[0] ≈ V[0] (没有来自未来 token 的污染) ----
    endtask

endclass

`endif // FLASHATTN_CAUSAL_CORNER_SEQ_SV
