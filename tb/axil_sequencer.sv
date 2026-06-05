// ==========================================================================
// axil_sequencer — AXI4-Lite Sequencer (UVM 组件)
// ==========================================================================
// 功能: 管理 Transaction 队列, 仲裁多个 Sequence, 将 Transaction
//       逐个发送给 Driver
//
// UVM 概念对照:
//   Sequencer = uvm_sequencer 的子类 (参数化: 处理哪种 Transaction)
//   功能很薄: UVM 框架自动处理大部分队列逻辑
//   主要作用是: Sequence 通过 `start(sequencer)` 把自己的 Transaction
//   注入到这个 Sequencer, 再由 Sequencer 排队发给 Driver
//
// 关系链:
//   Sequence.body()  →  `start_item(tx)` / `finish_item(tx)`
//                     →  Sequencer 内部队列
//                     →  Driver.seq_item_port.get_next_item(req)
//                     →  Driver 驱动到 DUT
// ==========================================================================

`ifndef AXIL_SEQUENCER_SV
`define AXIL_SEQUENCER_SV

class axil_sequencer extends uvm_sequencer #(axil_transfer);

    `uvm_component_utils(axil_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass

`endif // AXIL_SEQUENCER_SV
