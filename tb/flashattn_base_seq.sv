// ==========================================================================
// flashattn_base_seq — 基础 Sequence (UVM)
// ==========================================================================
// 功能: 封装 AXI4-Lite 寄存器读写的便捷方法
//       所有具体测试 Sequence 继承此类
//
// UVM 概念对照:
//   Sequence = uvm_sequence 的子类
//   body() 是核心: 描述"要做什么"
//   通过 `uvm_do_with(tx, {constraints}) 宏向 Sequencer 发送 Transaction
//   -- 这是 UVM 最常用的宏之一
//
// 常见宏:
//   `uvm_do(tx)            发送 tx (使用默认随机化)
//   `uvm_do_with(tx, {c})  发送 tx (带额外约束)
//   `uvm_create(tx)        只创建, 不发送
//   `uvm_send(tx)          发送已创建的 tx
// ==========================================================================

`ifndef FLASHATTN_BASE_SEQ_SV
`define FLASHATTN_BASE_SEQ_SV

class flashattn_base_seq extends uvm_sequence #(axil_transfer);

    `uvm_object_utils(flashattn_base_seq)

    function new(string name = "flashattn_base_seq");
        super.new(name);
    endfunction

    // ==================================================================
    // 便捷方法: AXI4-Lite 写寄存器
    // ==================================================================
    task write_reg(bit [7:0] addr, bit [31:0] data);
        axil_transfer tx;
        `uvm_do_with(tx, {
            kind == axil_transfer::WRITE;
            tx.addr == addr;
            tx.data == data;
        })
    endtask

    // ==================================================================
    // 便捷方法: AXI4-Lite 读寄存器
    // ==================================================================
    task read_reg(bit [7:0] addr, output bit [31:0] data);
        axil_transfer tx;
        `uvm_do_with(tx, {
            kind == axil_transfer::READ;
            tx.addr == addr;
        })
        data = tx.data;
    endtask

    // ==================================================================
    // 便捷方法: 等待 DONE
    // ==================================================================
    task wait_done(output bit [31:0] cycles);
        bit [31:0] status;
        int timeout = 500000;
        while (timeout > 0) begin
            read_reg(8'h04, status);
            if (status[1]) begin  // STATUS[1] = DONE
                read_reg(8'h40, cycles);
                return;
            end
            timeout--;
            #100;  // 100 个 time unit
        end
        `uvm_error("BASE_SEQ", "Timeout waiting for DONE")
    endtask

endclass

`endif // FLASHATTN_BASE_SEQ_SV
