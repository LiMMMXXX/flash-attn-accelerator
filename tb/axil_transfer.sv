// ==========================================================================
// axil_transfer — AXI4-Lite 传输 Transaction
// ==========================================================================
// 描述一次 AXI4-Lite 读写操作。
// 在 UVM 中，Transaction 是从 Sequencer → Driver 传递的数据包。
//
// UVM 概念对照:
//   Transaction  = uvm_sequence_item 的子类
//   一个 Transaction 对象 = 一次总线操作 (读或写)
//   Sequencer 负责"生产"Transaction, Driver 负责"消费"它
// ==========================================================================

`ifndef AXIL_TRANSFER_SV
`define AXIL_TRANSFER_SV

class axil_transfer extends uvm_sequence_item;

    // ---- 传输类型枚举 ----
    typedef enum bit {
        READ  = 1'b0,
        WRITE = 1'b1
    } kind_e;

    // ---- 随机化的成员变量 ----
    rand kind_e     kind;         // 读 or 写
    rand bit [7:0]  addr;         // 字节地址
    rand bit [31:0] data;         // 读写数据

    // 约束: 地址为 4 字节对齐 (AXI4-Lite 字访问)
    constraint c_addr_aligned { addr[1:0] == 2'b00; }

    // ---- 非随机成员 ----
    bit [1:0]       resp;         // AXI 响应码 (0=OKAY)

    // ==================================================================
    // UVM 宏: 注册到 factory (允许 factory override)
    //   uvm_object_utils_begin/end 让 UVM 自动处理
    //     - copy, compare, print, pack, unpack
    // ==================================================================
    `uvm_object_utils_begin(axil_transfer)
        `uvm_field_enum(kind_e, kind, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_DEFAULT)
        `uvm_field_int(data, UVM_DEFAULT)
        `uvm_field_int(resp, UVM_DEFAULT)
    `uvm_object_utils_end

    // 构造函数: 必须调用 super.new(name)
    function new(string name = "axil_transfer");
        super.new(name);
    endfunction

    // 可选: 自定义打印格式 (在仿真 log 中更易读)
    function string convert2string();
        if (kind == WRITE)
            return $sformatf("AXIL WRITE: addr=0x%02h data=0x%08h", addr, data);
        else
            return $sformatf("AXIL READ:  addr=0x%02h data=0x%08h resp=%0d",
                             addr, data, resp);
    endfunction

endclass

`endif // AXIL_TRANSFER_SV
