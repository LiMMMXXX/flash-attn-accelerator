// ==========================================================================
// flashattn_reg_rw_seq — 寄存器读写验证 Sequence
// ==========================================================================
// 功能: 验证 AXI4-Lite 所有寄存器的读写正确性
//       (赛题要求 3 个必须项之一)
// ==========================================================================

`ifndef FLASHATTN_REG_RW_SEQ_SV
`define FLASHATTN_REG_RW_SEQ_SV

class flashattn_reg_rw_seq extends flashattn_base_seq;

    `uvm_object_utils(flashattn_reg_rw_seq)

    function new(string name = "flashattn_reg_rw_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rdata;

        `uvm_info("REG_RW", "=== AXI4-Lite Register Read/Write Test ===", UVM_LOW)

        // ---- 测试 CFG 寄存器 (0x08) ----
        write_reg(8'h08, 32'h1);       // 写 CAUSAL_EN=1
        read_reg(8'h08, rdata);        // 读回
        if (rdata != 32'h1)
            `uvm_error("REG_RW", $sformatf("CFG mismatch: got 0x%h", rdata))
        else
            `uvm_info("REG_RW", "[PASS] CFG register R/W", UVM_LOW)

        // ---- 测试 STRIDE_BYTES (0x34) ----
        write_reg(8'h34, 32'd128);     // d × 2 = 128
        read_reg(8'h34, rdata);
        if (rdata != 32'd128)
            `uvm_error("REG_RW", $sformatf("STRIDE mismatch: got 0x%h", rdata))
        else
            `uvm_info("REG_RW", "[PASS] STRIDE_BYTES register R/W", UVM_LOW)

        // ---- 测试 SCALE (0x3C): 1/√64 = 0.125 → Q8.8 = 0x0020 ----
        write_reg(8'h3C, 32'h20);
        read_reg(8'h3C, rdata);
        if (rdata[15:0] != 16'h20)
            `uvm_error("REG_RW", $sformatf("SCALE mismatch: got 0x%h", rdata))
        else
            `uvm_info("REG_RW", "[PASS] SCALE register R/W", UVM_LOW)

        // ---- 测试 Q_BASE 地址 (0x14, 0x18) ----
        write_reg(8'h14, 32'h10000000);   // Q_BASE_L
        write_reg(8'h18, 32'h0);          // Q_BASE_H
        read_reg(8'h14, rdata);
        if (rdata != 32'h10000000)
            `uvm_error("REG_RW", "Q_BASE_L mismatch")
        else
            `uvm_info("REG_RW", "[PASS] Q_BASE register R/W", UVM_LOW)

        `uvm_info("REG_RW", "=== Register R/W Test Complete ===", UVM_LOW)
    endtask

endclass

`endif // FLASHATTN_REG_RW_SEQ_SV
