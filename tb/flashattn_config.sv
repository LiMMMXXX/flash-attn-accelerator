// ==========================================================================
// flashattn_config — FlashAttention 验证配置对象
// ==========================================================================
// 通过 uvm_config_db 传递验证参数 (序列长度、head维度、数据格式等)
// 用于在 test 和 env 之间共享配置。
//
// UVM 概念对照:
//   Config Object = 全局配置参数的容器
//   通过 uvm_config_db#(T)::set/get 在层次间传递
//   比全局变量安全, 比 module parameter 灵活
// ==========================================================================

`ifndef FLASHATTN_CONFIG_SV
`define FLASHATTN_CONFIG_SV

class flashattn_config extends uvm_object;

    // ---- 赛题固定参数 (默认值) ----
    int                 seq_len     = 256;      // 序列长度 S
    int                 head_dim    = 64;       // Head 维度 d

    // ---- Tile 配置 ----
    int                 tile_br     = 64;       // Q tile 行数
    int                 tile_bc     = 64;       // K/V tile 列数

    // ---- 测试配置 ----
    bit                 causal_en   = 1;        // 默认启用 causal mask
    int                 rand_seed   = 42;       // 随机种子
    int                 num_random_tests = 100; // 随机测试次数

    // ---- 数据格式 ----
    int                 q8p8_int_bits   = 7;    // Q8.8 整数位
    int                 q8p8_frac_bits  = 8;    // Q8.8 小数位

    // ---- 时序 ----
    int                 clk_period_ps  = 2000;  // 时钟周期 (ps) → 500 MHz

    // ---- 精度门限 ----
    real                max_mean_error = 0.03;  // mean_abs_error 上限
    real                max_max_error  = 0.10;  // max_abs_error 上限

    // ---- 超时 ----
    int                 sim_timeout_cycles = 500000;  // 仿真超时 (cycles)

    // 构造函数
    function new(string name = "flashattn_config");
        super.new(name);
    endfunction

    `uvm_object_utils_begin(flashattn_config)
        `uvm_field_int(seq_len, UVM_DEFAULT)
        `uvm_field_int(head_dim, UVM_DEFAULT)
        `uvm_field_int(tile_br, UVM_DEFAULT)
        `uvm_field_int(tile_bc, UVM_DEFAULT)
        `uvm_field_int(causal_en, UVM_DEFAULT)
        `uvm_field_int(rand_seed, UVM_DEFAULT)
        `uvm_field_int(num_random_tests, UVM_DEFAULT)
        `uvm_field_real(max_mean_error, UVM_DEFAULT)
        `uvm_field_real(max_max_error, UVM_DEFAULT)
        `uvm_field_int(sim_timeout_cycles, UVM_DEFAULT)
    `uvm_object_utils_end

endclass

`endif // FLASHATTN_CONFIG_SV
