// ==========================================================================
// flashattn_pkg — FlashAttention 硬件加速器全局包
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 全局参数定义 (S, d, Br, Bc, 位宽等)
//   - 定点数据类型定义 (Q8.8, Q8.24, Q16.16)
//   - 定点运算辅助函数 (格式转换、乘加、饱和)
//   - CSR 寄存器地址枚举
//   - AXI4 接口参数
//
// 数据格式: Q8.8 / Q8.24 / Q16.16 定点
//
// 参考:
//   - 赛题要求: ../题目要求.md
//   - 架构设计: ../docs/ARCHITECTURE.md
// ==========================================================================

`ifndef FLASHATTN_PKG_SV
`define FLASHATTN_PKG_SV

package flashattn_pkg;

    // ======================================================================
    // 1. 赛题固定参数 (Baseline: S=256, d=64)
    // ======================================================================
    localparam int S         = 256;   // 序列长度
    localparam int D         = 64;    // Head 维度
    localparam int BR        = 64;    // Q tile 行数 (Br)
    localparam int BC        = 64;    // K/V tile 列数 (Bc)
    localparam int N_TILES_I = 4;     // ceil(S/BR) = 256/64 = 4
    localparam int N_TILES_J = 4;     // ceil(S/BC) = 256/64 = 4
    localparam int TILES_TOTAL = 16;  // N_TILES_I × N_TILES_J

    // ======================================================================
    // 2. 定点数据位宽
    // ======================================================================
    localparam int Q8P8_W    = 16;    // Q8.8:  1-bit sign + 7-bit int + 8-bit frac
    localparam int Q8P24_W   = 32;    // Q8.24: 1-bit sign + 7-bit int + 24-bit frac
    localparam int Q16P16_W  = 32;    // Q16.16: 1-bit sign + 15-bit int + 16-bit frac
    localparam int ACC_W     = 40;    // 点积累加器: 64×Q8.8×Q8.8 需要40-bit防溢出

    // ======================================================================
    // 3. AXI4 接口参数
    // ======================================================================
    localparam int AXI_DATA_W = 64;   // AXI4 数据位宽 (8 bytes, 4×Q8.8)
    localparam int AXI_ADDR_W = 64;   // AXI4 地址位宽
    localparam int AXI_ID_W   = 4;    // AXI4 ID 位宽
    localparam int AXI_STRB_W = 8;    // AXI4 写选通位宽 (DATA_W/8)
    localparam int MAX_BURST_LEN = 16; // 最大 Burst 长度

    // ======================================================================
    // 4. SRAM 地址位宽
    // ======================================================================
    localparam int K_BUF_ADDR_W  = 12; // 64×64 = 4096 entries → 12-bit addr
    localparam int V_BUF_ADDR_W  = 12;
    localparam int Q_BUF_ADDR_W  = 12;
    localparam int O_ACC_ADDR_W  = 12;
    localparam int STAT_ADDR_W   = 8;  // 256 entries → 8-bit addr

    // ======================================================================
    // 5. 定点数据类型定义
    // ======================================================================
    typedef logic signed [Q8P8_W-1:0]    q8p8_t;    // Q8.8 有符号定点
    typedef logic signed [Q8P24_W-1:0]   q8p24_t;   // Q8.24 有符号定点
    typedef logic signed [Q16P16_W-1:0]  q16p16_t;  // Q16.16 有符号定点
    typedef logic signed [ACC_W-1:0]     acc40_t;   // 40-bit 扩展累加器

    // ======================================================================
    // 6. AXI4 类型定义 (简化)
    // ======================================================================
    typedef logic [AXI_ID_W-1:0]     axi_id_t;
    typedef logic [AXI_ADDR_W-1:0]   axi_addr_t;
    typedef logic [AXI_DATA_W-1:0]   axi_data_t;
    typedef logic [AXI_STRB_W-1:0]   axi_strb_t;

    // ======================================================================
    // 7. CSR 寄存器地址枚举
    // ======================================================================
    typedef enum logic [7:0] {
        CSR_CTRL         = 8'h00,  // 控制寄存器
        CSR_STATUS       = 8'h04,  // 状态寄存器 (只读)
        CSR_CFG          = 8'h08,  // 配置寄存器
        // 保留: 0x0C, 0x10
        CSR_Q_BASE_L     = 8'h14,  // Q 基地址低32位
        CSR_Q_BASE_H     = 8'h18,  // Q 基地址高32位
        CSR_K_BASE_L     = 8'h1C,  // K 基地址低32位
        CSR_K_BASE_H     = 8'h20,  // K 基地址高32位
        CSR_V_BASE_L     = 8'h24,  // V 基地址低32位
        CSR_V_BASE_H     = 8'h28,  // V 基地址高32位
        CSR_O_BASE_L     = 8'h2C,  // O 基地址低32位
        CSR_O_BASE_H     = 8'h30,  // O 基地址高32位
        CSR_STRIDE_BYTES = 8'h34,  // 行 stride (bytes)
        CSR_NEG_LARGE    = 8'h38,  // -inf 近似值 (Q8.8)
        CSR_SCALE        = 8'h3C,  // 1/√d 缩放常数 (Q8.8)
        CSR_CYCLES       = 8'h40   // 执行周期数 (只读)
    } csr_addr_t;

    // ======================================================================
    // 8. FSM 状态枚举 (主控状态机)
    // ======================================================================
    typedef enum logic [3:0] {
        MAIN_IDLE       = 4'h0,
        MAIN_INIT_STATS = 4'h1,
        MAIN_LOAD_KV    = 4'h2,
        MAIN_LOAD_Q     = 4'h3,
        MAIN_GEMM0      = 4'h4,
        MAIN_SOFTMAX    = 4'h5,
        MAIN_GEMM1      = 4'h6,
        MAIN_NEXT_Q     = 4'h7,
        MAIN_NEXT_KV    = 4'h8,
        MAIN_WRITEBACK  = 4'h9,
        MAIN_DONE       = 4'hA
    } main_state_t;

    // ======================================================================
    // 9. Q8.8 定点常量
    // ======================================================================
    // -inf:  Q8.8 最小有符号值 = -128.0
    localparam q8p8_t Q8P8_NEG_INF = 16'sh8000;
    localparam q8p8_t Q8P8_ZERO    = 16'sh0000;
    // 1/√64 = 1/8 = 0.125 = 0x0020 (32/256)
    localparam q8p8_t Q8P8_INV_SQRT_D = 16'h0020;

    // ======================================================================
    // 10. Q8.24 定点常量 (用于 exp 计算)
    // ======================================================================
    // ln(2)    ≈ 0.69314718 × 2^24 = 11629080 = 0x00B17218
    localparam q8p24_t Q8P24_LN2     = 32'sh00B17218;
    // 1/ln(2)  ≈ 1.44269504 × 2^24 = 24204406 = 0x01715476
    localparam q8p24_t Q8P24_INV_LN2 = 32'sh01715476;
    localparam q8p24_t Q8P24_ONE     = 32'sh01000000;
    localparam q8p24_t Q8P24_HALF    = 32'sh00800000;
    localparam q8p24_t Q8P24_INV6    = 32'sh002AAAAB;
    localparam q8p24_t Q8P24_INV24   = 32'sh000AAAAB;
    // exp 下溢阈值: -ln(2)×128 ≈ -88.72 → Q8.24 = 0xA74CCCCD
    localparam q8p24_t Q8P24_EXP_UF_THRESH = -32'sh574CCCCD;

    // ======================================================================
    // 11. 定点运算辅助函数
    // ======================================================================

    // ----------------------------------------------------------------
    // Q8.8 乘法 (返回 Q16.16 全精度)
    // ----------------------------------------------------------------
    function automatic q16p16_t mul_q8p8_full(input q8p8_t a, input q8p8_t b);
        mul_q8p8_full = $signed(a) * $signed(b);
    endfunction

    // ----------------------------------------------------------------
    // Q8.8 乘法 (截断回 Q8.8, 四舍五入)
    // ----------------------------------------------------------------
    function automatic q8p8_t mul_q8p8(input q8p8_t a, input q8p8_t b);
        logic signed [31:0] prod_full;
        prod_full = $signed(a) * $signed(b);
        // 取 [15:8] + 四舍五入 (bit 7)
        mul_q8p8 = q8p8_t'(prod_full[15:8] + {15'd0, prod_full[7]});
    endfunction

    // ----------------------------------------------------------------
    // Q8.8 → Q8.24 扩展 (符号扩展 + 左移16位)
    // ----------------------------------------------------------------
    function automatic q8p24_t q8p8_to_q8p24(input q8p8_t val);
        q8p8_to_q8p24 = {{16{val[15]}}, val[15:0]} <<< 16;
    endfunction

    // ----------------------------------------------------------------
    // Q8.24 → Q8.8 截断 (带饱和, 四舍五入)
    // ----------------------------------------------------------------
    function automatic q8p8_t q8p24_to_q8p8(input q8p24_t val);
        logic signed [23:0] rounded;
        // 四舍五入: 检查 bit 7
        rounded = val[23:0] + {16'd0, val[7]};
        if (val > 32'sd32767)
            q8p24_to_q8p8 = 16'sh7FFF;       // 正饱和
        else if (val < -32'sd32768)
            q8p24_to_q8p8 = 16'sh8000;       // 负饱和
        else
            q8p24_to_q8p8 = rounded[23:8];   // 取 [23:8] 位
    endfunction

    // ----------------------------------------------------------------
    // Q16.16 → Q8.8 截断 (带饱和, 四舍五入)
    // ----------------------------------------------------------------
    function automatic q8p8_t q16p16_to_q8p8(input q16p16_t val);
        logic signed [23:0] rounded;
        rounded = val[23:0] + {16'd0, val[7]};
        if (val > 32'sd32767)
            q16p16_to_q8p8 = 16'sh7FFF;
        else if (val < -32'sd32768)
            q16p16_to_q8p8 = 16'sh8000;
        else
            q16p16_to_q8p8 = rounded[23:8];
    endfunction

    // ----------------------------------------------------------------
    // 最大值比较 (Q8.8)
    // ----------------------------------------------------------------
    function automatic q8p8_t max_q8p8(input q8p8_t a, input q8p8_t b);
        max_q8p8 = ($signed(a) > $signed(b)) ? a : b;
    endfunction

endpackage

`endif // FLASHATTN_PKG_SV
