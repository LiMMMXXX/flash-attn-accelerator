// ==========================================================================
// flashattn_tb_pkg — FlashAttention UVM 验证包
// ==========================================================================
// 包含:
//   1. UVM import & 宏定义
//   2. 所有 Transaction 类型
//   3. 所有组件的 include
//   4. 测试类型定义
//
// UVM 层次结构:
//   uvm_test (test_flashattn_basic / test_flashattn_random)
//     └── flashattn_env
//           ├── axil_agent (active)
//           │     ├── axil_sequencer
//           │     ├── axil_driver
//           │     └── axil_monitor
//           ├── axi4_mem_agent (passive — 仅 Monitor)
//           │     └── axi4_mem_monitor
//           ├── flashattn_scoreboard
//           └── flashattn_coverage
// ==========================================================================

`ifndef FLASHATTN_TB_PKG_SV
`define FLASHATTN_TB_PKG_SV

`timescale 1ns / 1ps

// ======================================================================
// 1. UVM 导入
// ======================================================================
import uvm_pkg::*;

// ======================================================================
// 2. 包含所有文件 (按依赖顺序)
// ======================================================================

// ---- 接口 ----
`include "axil_if.sv"
`include "axi4_mem_if.sv"

// ---- Transaction 定义 ----
`include "axil_transfer.sv"
`include "axi4_mem_trans.sv"
`include "flashattn_config.sv"

// ---- UVM 组件 ----
`include "axil_driver.sv"
`include "axil_monitor.sv"
`include "axil_sequencer.sv"
`include "axil_agent.sv"

`include "axi4_mem_driver.sv"
`include "axi4_mem_monitor.sv"
`include "axi4_mem_agent.sv"

`include "flashattn_scoreboard.sv"
`include "flashattn_coverage.sv"
`include "flashattn_env.sv"

// ---- 测试序列 ----
`include "flashattn_base_seq.sv"
`include "flashattn_reg_rw_seq.sv"
`include "flashattn_rand_seq.sv"
`include "flashattn_causal_corner_seq.sv"

// ---- 测试 ----
`include "test_flashattn_basic.sv"
`include "test_flashattn_random.sv"
`include "test_flashattn_complete.sv"

`endif // FLASHATTN_TB_PKG_SV
