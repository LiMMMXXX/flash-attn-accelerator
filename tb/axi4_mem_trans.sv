// ==========================================================================
// axi4_mem_trans — AXI4-Master 内存传输 Transaction
// ==========================================================================
// 描述一次 AXI4 burst 传输。用于 Monitor 捕获 DUT 发出的 DMA 操作。
// ==========================================================================

`ifndef AXI4_MEM_TRANS_SV
`define AXI4_MEM_TRANS_SV

class axi4_mem_trans extends uvm_sequence_item;

    typedef enum bit {
        READ  = 1'b0,
        WRITE = 1'b1
    } kind_e;

    rand kind_e         kind;
    rand bit [63:0]     addr;           // 起始地址
    rand bit [7:0]      burst_len;      // Burst 长度 (0 = 1 beat)
    rand bit [2:0]      burst_size;     // 每 beat 字节数 (3'd3 = 8 bytes)
    rand bit [63:0]     data[];         // 动态数组, 实际数据
    rand bit [7:0]      strb[];         // 写选通

    // 约束: burst 长度合理
    constraint c_burst_len { burst_len inside {[0:15]}; }
    // 约束: data/strb 数组大小等于 burst_len + 1
    constraint c_data_size { data.size() == burst_len + 1; }
    constraint c_strb_size { strb.size() == burst_len + 1; }

    bit [1:0]           resp;
    int                 latency;        // 响应延迟 (cycle 数)

    `uvm_object_utils_begin(axi4_mem_trans)
        `uvm_field_enum(kind_e, kind, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_DEFAULT)
        `uvm_field_int(burst_len, UVM_DEFAULT)
        `uvm_field_int(burst_size, UVM_DEFAULT)
        `uvm_field_queue_int(data, UVM_DEFAULT)
        `uvm_field_queue_int(strb, UVM_DEFAULT)
        `uvm_field_int(latency, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "axi4_mem_trans");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("AXI4 %s: addr=0x%0h len=%0d size=%0d bytes=%0d",
                         kind.name(), addr, burst_len, 2**burst_size,
                         2**burst_size * (burst_len + 1));
    endfunction

endclass

`endif // AXI4_MEM_TRANS_SV
