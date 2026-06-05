// ==========================================================================
// perf_counters — 性能计数器模块 (7 路统计)
// ==========================================================================
// 作者:     Cowork 3P
// 日期:     2026-06-05
// 版本:     1.0
//
// 功能描述:
//   - 统计 FlashAttention 计算过程中的 7 个性能指标
//   - 在 MAIN_DONE 时锁存所有计数值
//   - 通过 CSR 可读 (CYCLES 寄存器 + 扩展性能寄存器)
//
// 计数器列表:
//   1. PERF_CYCLES:       总执行周期数
//   2. PERF_GEMM_CYCLES:  GEMM0+GEMM1 总周期数
//   3. PERF_SOFTMAX_CYCLES: Softmax 总周期数
//   4. PERF_STALL_CYCLES: GEMM 等待 Softmax 的停等周期 (目标: 0)
//   5. PERF_MEM_STALLS:   DMA/内存停等周期
//   6. PERF_TILES:        处理的 tile 总数
//   7. PERF_EXP_OPS:      exp 操作总次数
//
// 接口: 事件输入 + 控制 + 寄存器输出
//
// 关键设计决策:
//   - 使用事件驱动计数 (evt_*), 避免 FSM 直接操作计数器
//   - LATCH 机制: MAIN_DONE 时锁存, 防止下一轮计算覆盖
//   - PERF_STALL_CYCLES = 0 为目标, 证明 softmax 没有阻塞 GEMM
//
// 参考:
//   - 赛题要求: ../题目要求.md
//   - 架构设计: ../docs/ARCHITECTURE.md
// ==========================================================================

`ifndef PERF_COUNTERS_SV
`define PERF_COUNTERS_SV

`timescale 1ns / 1ps

module perf_counters (
    // ---- 时钟 & 复位 ----
    input  logic         clk,
    input  logic         rst_n,

    // ---- 控制 ----
    input  logic         cnt_clear,     // 清零所有计数器
    input  logic         cnt_latch,     // 锁存当前计数值 (MAIN_DONE 触发)
    input  logic         cycle_en,      // 周期计数使能 (BUSY 期间)

    // ---- 事件输入 ----
    input  logic         evt_gemm0_cycle,    // GEMM0 在此周期活跃
    input  logic         evt_softmax_cycle,  // Softmax 在此周期活跃
    input  logic         evt_gemm1_cycle,    // GEMM1 在此周期活跃
    input  logic         evt_stall_cycle,    // GEMM 等待 Softmax 的停等周期
    input  logic         evt_mem_stall,      // DMA/内存停等周期
    input  logic         evt_tile_done,      // 一个 tile 完成
    input  logic         evt_exp_op,         // 一次 exp 操作

    // ---- 寄存器输出 (锁存后稳定) ----
    output logic [31:0]  perf_cycles,        // 总周期
    output logic [31:0]  perf_gemm_cycles,   // GEMM 周期
    output logic [31:0]  perf_softmax_cycles, // Softmax 周期
    output logic [31:0]  perf_stall_cycles,  // 停等周期 ★
    output logic [31:0]  perf_mem_stalls,    // 内存停等
    output logic [31:0]  perf_tiles,         // Tile 总数
    output logic [31:0]  perf_exp_ops        // Exp 操作数
);

    // ======================================================================
    // 内部计数器 (运行中)
    // ======================================================================
    // cnt_cycles, cnt_gemm, cnt_softmax, cnt_stall, cnt_mem, cnt_tiles, cnt_exp

    // ======================================================================
    // 锁存寄存器 (在 LATCH 时更新)
    // ======================================================================
    // latched_cycles, latched_gemm, ... (连接到输出)

    // ======================================================================
    // 计数逻辑:
    //   if (cnt_clear) → 清零
    //   else if (cycle_en):
    //     cnt_cycles++
    //     if (evt_gemm0_cycle || evt_gemm1_cycle) cnt_gemm++
    //     if (evt_softmax_cycle) cnt_softmax++
    //     if (evt_stall_cycle) cnt_stall++
    //     if (evt_mem_stall) cnt_mem++
    //     if (evt_tile_done) cnt_tiles++
    //     if (evt_exp_op) cnt_exp += 1
    // ======================================================================

    // ======================================================================
    // 锁存逻辑:
    //   if (cnt_latch) → 将当前计数值锁存到输出寄存器
    // ======================================================================

endmodule

`endif // PERF_COUNTERS_SV
