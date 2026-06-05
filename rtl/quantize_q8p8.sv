// ==========================================================================
// quantize_q8p8 — 定点量化单元 (Q16.16 → Q8.8)
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 将 Q16.16 (32-bit) 格式的 O 累加器结果量化为 Q8.8 (16-bit)
//   - 带四舍五入 (检查截断位 bit 7)
//   - 带饱和保护 (超出 Q8.8 表示范围时钳位)
//
// 数据格式:
//   输入:  Q16.16 (32-bit 有符号), 范围 [-32768, +32767.999]
//   输出:  Q8.8 (16-bit 有符号), 范围 [-128, +127.996]
//
// 接口: 流式 valid-ready
//
// 量化过程:
//   1. 四舍五入: rounded = val + (bit 7 ? 1 : 0)
//   2. 截断:   取 rounded[23:8] 位 (Q16.16 → Q8.8)
//   3. 饱和:   正溢出 → 0x7FFF (127.996), 负溢出 → 0x8000 (-128.0)
//
// 关键设计决策:
//   - 使用舍入而非截断, 减少系统性偏置误差
//   - 1 cycle 延迟, 组合逻辑路径较短
//   - 饱和保护可防止静默溢出
//
// 参考:
//   - 架构设计: ../docs/ARCHITECTURE.md §5.1
// ==========================================================================

`ifndef QUANTIZE_Q8P8_SV
`define QUANTIZE_Q8P8_SV

`timescale 1ns / 1ps

module quantize_q8p8 #(
    parameter int INPUT_WIDTH  = 32,   // Q16.16
    parameter int OUTPUT_WIDTH = 16    // Q8.8
) (
    // ---- 时钟 & 复位 ----
    input  logic                         clk,
    input  logic                         rst_n,

    // ---- 数据输入 (Q16.16) ----
    input  logic signed [INPUT_WIDTH-1:0]  data_in,
    input  logic                           data_valid,

    // ---- 数据输出 (Q8.8) ----
    output logic signed [OUTPUT_WIDTH-1:0] data_out,
    output logic                           data_valid_out
);

    // ======================================================================
    // 量化逻辑:
    //   1. 四舍五入: rounded = data_in[23:0] + {16'd0, data_in[7]}
    //   2. 截断:    result = rounded[23:8]
    //   3. 饱和:    if (data_in > 32'd32767)      → 16'h7FFF
    //              else if (data_in < -32'd32768)  → 16'h8000
    //              else                            → result[15:0]
    // ======================================================================

endmodule

`endif // QUANTIZE_Q8P8_SV
