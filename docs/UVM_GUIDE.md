# UVM 学习指南 — 基于 FlashAttention 加速器验证项目

> **目标**: 通过本项目的真实验证环境，从零学习 UVM 验证方法学
> **前提**: 熟悉 SystemVerilog 基础，了解数字电路设计
> **项目**: FlashAttention 硬件加速器 IP (Cadence 赛题)

---

## 目录

1. [UVM 是什么？为什么需要它？](#1-uvm-是什么为什么需要它)
2. [UVM 核心概念速览](#2-uvm-核心概念速览)
3. [本项目的 UVM 验证架构](#3-本项目的-uvm-验证架构)
4. [从零搭建：一步步理解每个文件](#4-从零搭建一步步理解每个文件)
5. [模块开发中的测试策略](#5-模块开发中的测试策略)
6. [运行 UVM 仿真](#6-运行-uvm-仿真)
7. [常见问题与调试技巧](#7-常见问题与调试技巧)

---

## 1. UVM 是什么？为什么需要它？

### 1.1 问题：没有 UVM 时怎么验证？

```systemverilog
// 传统方式: 在 testbench 中手写时序
module old_style_tb;
    reg clk;
    reg [7:0] addr;
    reg [31:0] data;

    initial begin
        clk = 0;
        #10 addr = 8'h04;
        #10 data = 32'h1234;
        // 每次加新测试都要改这个 initial block
        // 没有复用, 难以维护
    end
endmodule
```

问题很明显：测试逻辑和时序混在一起，每加一个测试都要改同一个文件，不可复用、不可扩展。

### 1.2 UVM 的解决思路

UVM 把验证任务拆成**可复用的组件**：

```
"我要测一个 AXI4-Lite 外设"
  → 需要发 AXI4-Lite 读写请求     → axil_driver    (负责驱动信号)
  → 需要监控总线上的实际活动      → axil_monitor   (负责观测)
  → 需要编排"先写 CTRL, 再等 DONE" → Sequence       (负责编排操作)
  → 需要对比 DUT 输出和预期值    → Scoreboard     (负责检查)
  → 需要收集覆盖率              → Coverage       (负责度量)
```

每个组件各司其职，可以在不同项目中重用。

### 1.3 本项目中 UVM 的角色

```
┌─────────────────────────────────────────────────┐
│                  UVM Testbench                    │
│                                                  │
│  uvm_test (test_flashattn_complete)              │
│    │                                             │
│    └── flashattn_env                             │
│          ├── axil_agent (active)                 │
│          │     ├── axil_sequencer  ← Sequence    │
│          │     ├── axil_driver     → DUT pins    │
│          │     └── axil_monitor    → Scoreboard  │
│          │                                       │
│          ├── axi4_mem_agent                      │
│          │     ├── axi4_mem_driver  ←→ AXI bus   │
│          │     └── axi4_mem_monitor → Scoreboard │
│          │                                       │
│          ├── flashattn_scoreboard                │
│          └── flashattn_coverage                  │
│                                                  │
│  DUT: flashattn_top                              │
│    ← AXI4-Lite (axil_if)                         │
│    → AXI4-Master (axi4_mem_if)                   │
└─────────────────────────────────────────────────┘
```

---

## 2. UVM 核心概念速览

### 2.1 对象 vs 组件

| | uvm_object | uvm_component |
|---|---|---|
| 生命周期 | 临时的, 用完即弃 | 永久的, 存在于整个仿真 |
| 层次结构 | 无 parent | 有 parent (树状结构) |
| 例子 | Transaction, Sequence, Config | Driver, Monitor, Env, Test |
| phase 机制 | 无 | 有 (build → connect → run → ...) |

```systemverilog
// uvm_object 例子 (Transaction — 一次总线操作)
class axil_transfer extends uvm_sequence_item;  // uvm_sequence_item ← uvm_object
    rand bit [7:0]  addr;
    rand bit [31:0] data;
    // ...
endclass

// uvm_component 例子 (Driver — 贯穿整个仿真)
class axil_driver extends uvm_driver #(axil_transfer);  // uvm_driver ← uvm_component
    // ...
endclass
```

### 2.2 Phase 机制

UVM 有固定的执行顺序，不需要手动管理：

```
build_phase      → 创建子组件、获取配置
connect_phase    → 连接 TLM 端口 (Monitor → Scoreboard)
end_of_elaboration → 打印拓扑结构
start_of_simulation → 仿真开始前
run_phase        → ★ 核心: 实际仿真运行
  (pre_reset → reset → post_reset → pre_configure → configure
   → post_configure → pre_main → main → post_main
   → pre_shutdown → shutdown → post_shutdown)
extract_phase    → 提取结果
check_phase      → 检查结果
report_phase     → 打印报告
```

**关键**: `run_phase` 是 task (可以耗时), 其他 phase 是 function (不可耗时)。

### 2.3 config_db — UVM 的"全局配置通道"

config_db 是一个键值对存储，解决"如何把 interface 传给所有子组件"的问题：

```systemverilog
// 在 test_top module 中设置 (非 UVM)
uvm_config_db#(virtual axil_if)::set(null, "*", "axil_vif", axil_vif);

// 在 axil_driver build_phase 中获取
uvm_config_db#(virtual axil_if.master)::get(this, "", "axil_vif", vif);
```

`set` 的参数: `(context, instance_path, field_name, value)`
- `null, "*"` 表示对所有组件可见

### 2.4 TLM — 组件间通信

```
Sequence.body()
    │  start_item / finish_item
    ▼
Sequencer (仲裁)
    │  seq_item_port.get_next_item()
    ▼
Driver (驱动到 DUT)
    │  seq_item_port.item_done()
    ▼
Monitor (观测 DUT 输出)
    │  ap.write(transaction)           ← analysis_port 广播
    ▼
Scoreboard (接收并检查)
    ▲  analysis_imp.write(transaction) ← analysis_import 接收
```

**TLM 端口类型**:
- `uvm_seq_item_pull_port` — Sequencer → Driver (一对一，拉取模式)
- `uvm_analysis_port` — Monitor → Scoreboard/Coverage (一对多，广播模式)

### 2.5 objection — 控制仿真何时结束

```systemverilog
task run_phase(uvm_phase phase);
    phase.raise_objection(this);   // "我还有工作!"
    seq.start(env.axil_agt.sequencer);
    phase.drop_objection(this);    // "我完成了, 可以结束了"
endtask
```

当所有 component 都 drop 了 objection，UVM 认为仿真可以结束。

---

## 3. 本项目的 UVM 验证架构

### 3.1 文件清单与功能对照

| 文件 | 类型 | 功能 | UVM 基类 |
|------|------|------|---------|
| `axil_if.sv` | Interface | AXI4-Lite 信号定义 + modport | — |
| `axi4_mem_if.sv` | Interface | AXI4-Master 信号定义 + modport | — |
| `axil_transfer.sv` | Transaction | 一次 AXI4-Lite 读写操作 | uvm_sequence_item |
| `axi4_mem_trans.sv` | Transaction | 一次 AXI4 burst 传输 | uvm_sequence_item |
| `flashattn_config.sv` | Config Object | 验证参数 (S/d/tile/精度门限) | uvm_object |
| `axil_driver.sv` | Driver | 驱动 AXI4-Lite 信号 | uvm_driver |
| `axil_monitor.sv` | Monitor | 观测 AXI4-Lite 总线 | uvm_monitor |
| `axil_sequencer.sv` | Sequencer | 管理 Transaction 队列 | uvm_sequencer |
| `axil_agent.sv` | Agent | 封装 Driver+Sequencer+Monitor | uvm_agent |
| `axi4_mem_driver.sv` | Driver | 模拟 DDR (响应 DUT 读写) | uvm_driver |
| `axi4_mem_monitor.sv` | Monitor | 观测 DUT 的 DMA 活动 | uvm_monitor |
| `axi4_mem_agent.sv` | Agent | 封装 DDR Driver+Monitor | uvm_agent |
| `flashattn_base_seq.sv` | Sequence | 提供 write_reg/read_reg 便捷方法 | uvm_sequence |
| `flashattn_reg_rw_seq.sv` | Sequence | 寄存器读写测试 | uvm_sequence |
| `flashattn_rand_seq.sv` | Sequence | 随机 Q/K/V 端到端测试 | uvm_sequence |
| `flashattn_causal_corner_seq.sv` | Sequence | Causal mask 边界测试 | uvm_sequence |
| `flashattn_scoreboard.sv` | Scoreboard | 对比 DUT 输出 vs golden | uvm_scoreboard |
| `flashattn_coverage.sv` | Coverage | 功能覆盖率收集 | uvm_subscriber |
| `flashattn_env.sv` | Env | 实例化所有组件 | uvm_env |
| `test_flashattn_basic.sv` | Test | 基础测试 | uvm_test |
| `test_flashattn_random.sv` | Test | 随机测试 | uvm_test |
| `test_flashattn_complete.sv` | Test | 完整回归 (3 项) | uvm_test |
| `test_top.sv` | Module | 顶层: 时钟+DUT+interface → UVM | — |
| `flashattn_tb_pkg.sv` | Package | 汇总所有 include | — |
| `Makefile` | Script | Xcelium 编译/仿真命令 | — |

### 3.2 数据流

```
                               ┌──────────────┐
                               │  Golden      │
                               │  Model       │
                               │  (Python/NumPy)│
                               └──────┬───────┘
                                      │ 预期 O 输出
                                      ▼
                              ┌───────────────┐
                              │  Scoreboard   │
                              │  对比 DUT vs  │
                              │  Golden       │
                              └───────┬───────┘
                                      ▲
                         Monitor 广播  │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
              axil_monitor      axi4_mem_monitor      (更多...)
              (AXI4-Lite 总线)  (DMA 总线)
                    ▲                 ▲
                    │                 │
              ┌─────┴─────┐    ┌─────┴──────────┐
              │ DUT       │    │ DDR Model       │
              │ flashattn │◄──►│ (axi4_mem_driver)│
              │ _top      │    └────────────────┘
              └─────┬─────┘
                    ▲
                    │
              ┌─────┴─────┐
              │ axil_driver│
              │ (Sequence→ │
              │  DUT pins) │
              └────────────┘
```

---

## 4. 从零搭建：一步步理解每个文件

### 步骤 1: Interface — 连接 DUT 和 UVM 的桥梁

```systemverilog
interface axil_if (input logic clk, input logic rst_n);
    logic [7:0]  awaddr;    // 写地址
    logic        awvalid;   // 写地址有效
    logic        awready;   // 写地址就绪
    // ... 更多信号

    modport master (...);    // Driver 用 (可驱动)
    modport slave (...);     // DUT 用 (被动接收)
    modport monitor (...);   // Monitor 用 (只读)
endinterface
```

**关键点**: `modport` 控制谁能写/谁能读，防止多驱冲突。

### 步骤 2: Transaction — 描述"一次操作"

```systemverilog
class axil_transfer extends uvm_sequence_item;
    rand bit [7:0]  addr;    // 地址 — rand 表示可以随机化
    rand bit [31:0] data;    // 数据

    constraint c_addr_aligned { addr[1:0] == 2'b00; }  // 约束: 4字节对齐
    `uvm_object_utils_begin(axil_transfer) ...
endclass
```

**关键点**: `rand` + `constraint` = UVM 可以自动生成符合约束的随机数据。

### 步骤 3: Driver — 把 Transaction 变成信号跳变

```systemverilog
class axil_driver extends uvm_driver #(axil_transfer);
    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);   // 从 Sequencer 拿
            if (req.kind == WRITE)
                do_write(req);                  // 驱动 AXI4-Lite 写时序
            else
                do_read(req);                   // 驱动 AXI4-Lite 读时序
            seq_item_port.item_done();          // 告诉 Sequencer "完成"
        end
    endtask
endclass
```

**关键点**: `get_next_item` 是阻塞的 → 没有 Transaction 时 Driver 自动等待。

### 步骤 4: Monitor — 从信号跳变还原 Transaction

```systemverilog
class axil_monitor extends uvm_monitor;
    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            if (vif.bvalid && vif.bready) begin
                tx = axil_transfer::type_id::create("tx");
                tx.kind = WRITE;
                ap.write(tx);  // 广播! Scoreboard 自动收到
            end
        end
    endtask
endclass
```

**关键点**: Monitor 不驱动信号，只观测。`ap.write()` 是广播。

### 步骤 5: Agent — 打包 Driver + Sequencer + Monitor

```systemverilog
class axil_agent extends uvm_agent;
    axil_driver     driver;       // 可选 (is_active 控制)
    axil_sequencer  sequencer;    // 可选
    axil_monitor    monitor;      // 必须

    function void build_phase(uvm_phase phase);
        monitor = axil_monitor::type_id::create("monitor", this);
        if (get_is_active()) begin
            driver    = axil_driver::type_id::create("driver", this);
            sequencer = axil_sequencer::type_id::create("sequencer", this);
        end
    endfunction
endclass
```

**关键点**: Agent 把 "AXI4-Lite 的一切"打包。想测 DUT 的 Slave 接口? 实例化 axil_agent 并设 is_active=UVM_ACTIVE。

### 步骤 6: Sequence — "做什么"的剧本

```systemverilog
class flashattn_reg_rw_seq extends flashattn_base_seq;
    task body();
        write_reg(8'h08, 32'h1);       // 写 CFG
        read_reg(8'h08, rdata);        // 读回验证
        if (rdata != 32'h1)
            `uvm_error(...)            // 验证失败
    endtask
endclass
```

**关键点**: Sequence 不碰信号！只调用 `write_reg`/`read_reg` 这种高层抽象。

### 步骤 7: Scoreboard — "对不对"的裁判

```systemverilog
class flashattn_scoreboard extends uvm_scoreboard;
    function void compare_results();
        for (r = 0; r < S; r++)
            for (c = 0; c < d; c++)
                abs_err = |dut_O[r][c] - golden_O[r][c]|;
        assert(mean_abs_error < 0.03);   // 赛题精度验收
    endfunction
endclass
```

### 步骤 8: Env — "所有东西的容器"

```systemverilog
class flashattn_env extends uvm_env;
    axil_agent       axil_agt;     // AXI4-Lite Agent
    axi4_mem_agent   mem_agt;      // DDR 模拟 Agent
    flashattn_scoreboard scoreboard;
    flashattn_coverage   coverage;
endclass
```

### 步骤 9: Test — "运行哪个测试"

```systemverilog
class test_flashattn_complete extends uvm_test;
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        // 运行 3 个 Sequence (赛题要求)
        seq_reg.start(env.axil_agt.sequencer);
        seq_rand.start(env.axil_agt.sequencer);
        seq_causal.start(env.axil_agt.sequencer);
        phase.drop_objection(this);
    endtask
endclass
```

### 步骤 10: test_top — 硬件 + UVM 的汇合点

```systemverilog
module test_top;
    // 1. 时钟和复位
    // 2. Interface 实例化
    // 3. DUT 实例化, 连接到 interface
    // 4. uvm_config_db::set() — 把 interface 传给 UVM 世界
    // 5. run_test() — 启动 UVM
endmodule
```

---

## 5. 模块开发中的测试策略

你问过"开发中怎么测小模块"。在 UVM 框架下：

### 5.1 方式 A: 轻量 cocotb (推荐用于模块级调试)

```python
# 快速验证 pipelined_exp_fixed 的精度
@cocotb.test()
async def test_exp_precision(dut):
    for _ in range(1000):
        x = -np.random.rand() * 20.0
        dut.x_in.value = int(x * 2**24)  # Q8.24
        await ClockCycles(dut.clk, 6)    # 等 5 级流水线
        hw = int(dut.y_out.value) / 2**24
        assert abs(hw - np.exp(x)) / np.exp(x) < 2e-5
```

### 5.2 方式 B: UVM 单模块 Test (推荐用于集成前)

为单个模块写一个精简的 UVM test:

```systemverilog
class test_exp_unit extends uvm_test;
    task run_phase(uvm_phase phase);
        // 直接用 DPI-C 调用 Python golden, 或者手写定向测试
        // 不需要完整的 AXI agent，直接 toggle 信号
    endtask
endclass
```

### 5.3 方式 C: 使用现有 UVM Env (集成后)

等 top 层集成完成，直接复用 `flashattn_env` + 自定义 Sequence:

```systemverilog
class exp_precision_seq extends flashattn_base_seq;
    task body();
        // 配置 DUT, 加载特殊 pattern, 启动, 检查 exp_ops counter
    endtask
endclass
```

**推荐顺序**: 模块写好 → cocotb 快速验证 → 集成到 top → UVM 端到端验证。

---

## 6. 运行 UVM 仿真

### 6.1 命令行

```bash
# 进入 tb 目录
cd tb

# 基础测试 (寄存器读写)
make test_basic

# 随机端到端测试
make test_random

# 完整回归 (赛题 3 项全部)
make test_complete

# GUI 模式 (看波形)
make xrun_gui
```

### 6.2 Xcelium 命令行参数解释

```bash
xrun -64bit                    # 64-bit 模式
     -uvm                      # 启用 UVM
     +UVM_TESTNAME=test_xxx    # 指定运行哪个 Test
     +UVM_VERBOSITY=UVM_MEDIUM # 日志级别
     -timescale 1ns/1ps        # 时间单位
     -access +rwc              # 允许波形访问
     -gui                      # GUI 模式
```

---

## 7. 常见问题与调试技巧

### Q1: "Virtual interface not found in config_db"

**原因**: config_db 的 set 和 get 路径不匹配。

**解决**:
```systemverilog
// set 时使用通配符
uvm_config_db#(virtual axil_if)::set(null, "*", "axil_vif", axil_vif);
// 或者精确匹配路径
uvm_config_db#(virtual axil_if)::set(null, "uvm_test_top.env.axil_agt", "axil_vif", axil_vif);
```

### Q2: 仿真立即结束 (什么都没有发生)

**原因**: 忘记 `raise_objection`。

**解决**: 在 Sequence body 开头 `raise_objection`, 结尾 `drop_objection`。

### Q3: AXI4-Lite 握手死锁

**原因**: VALID 信号一直在等 READY, 或反之。

**解决**: `do_write` 中不要同时等 VALID 和 READY，分步等待:
```systemverilog
vif.awvalid <= 1;
@(posedge vif.clk);
while (!vif.awready) @(posedge vif.clk);  // 只等 READY
vif.awvalid <= 0;
```

### Q4: 怎么调试 UVM?

1. **提高 VERBOSITY**: `+UVM_VERBOSITY=UVM_HIGH` 看更多日志
2. **看波形**: `make xrun_gui` 打开 GUI
3. **设断点**: 在 Xcelium GUI 中点选信号 → 加 watch
4. **`uvm_info` 打印**: 在可疑位置加 `uvm_info("DEBUG", ...)`

### Q5: Scoreboard 没有收到数据

**原因**: Monitor 的 `ap.write()` 没有连接或条件不满足。

**检查**:
- connect_phase 中是否连接了 `monitor.ap.connect(scoreboard.xxx_imp)`
- Monitor 中的 `if (vif.bvalid && vif.bready)` 条件是否满足

---

## 8. 下一步

1. **阅读本项目的 tb/ 目录**, 每个文件开头都有详细注释说明其 UVM 角色
2. **先跑通 test_flashattn_basic** (寄存器读写, 不依赖 DUT 功能)
3. **逐步填充 RTL**, 每完成一个模块跑对应的 Sequence
4. **最后跑 test_flashattn_complete** 完成全部 3 项赛题要求

祝学习顺利！
