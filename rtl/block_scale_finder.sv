// ==========================================================================
// block_scale_finder — 块缩放因子查找单元 (可选模块)
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 流式扫描 tile 内元素, 找到最大绝对值 (absmax)
//   - 用于 FP8/INT8 块量化时计算缩放因子
//   - Baseline 阶段为可选模块 (Q8.8 定点不需要块缩放)
//   - 在 Bonus 项 (FP8/INT8) 中使用
//
// 数据格式:
//   输入:  32-bit (FP32 或高精度定点)
//   输出:  30-bit absmax (无符号位)
//
// 接口: 流式 valid-ready
//
// 关键设计决策:
//   - 使用 running maximum 而非全存储, 面积微小
//   - 延迟 1 cycle (比较+更新)
//   - 在 tile 结束时输出 absmax
//
// 参考:
//   - Bonus 项: 赛题要求 §2.3 Item 7 (INT8/FP8)
// ==========================================================================

`ifndef BLOCK_SCALE_FINDER_SV
`define BLOCK_SCALE_FINDER_SV

`timescale 1ns / 1ps

module block_scale_finder #(
    parameter int TILE_ELEMS = 4096   // Br × Bc = 4096
) (
    // ---- 时钟 & 复位 ----
    input  logic         clk,
    input  logic         rst_n,

    // ---- 控制 ----
    input  logic         start,          // 开始扫描新 tile
    input  logic [31:0]  elem_in,        // 输入元素
    input  logic         elem_valid,     // 元素有效
    input  logic         elem_last,      // tile 最后一个元素

    // ---- 输出 ----
    output logic [30:0]  absmax_out,     // 最大绝对值 (31-bit unsigned)
    output logic         absmax_valid,   // 输出有效
    output logic [31:0]  count           // 已扫描元素数
);

    // ======================================================================
    // 逻辑:
    //   running_max = max(running_max, |elem_in|)
    //   在 elem_last 时输出 running_max
    // ======================================================================

endmodule

`endif // BLOCK_SCALE_FINDER_SV
