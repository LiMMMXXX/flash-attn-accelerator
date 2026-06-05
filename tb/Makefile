# UVM 仿真脚本 — FlashAttention 验证环境
# 使用: make -f Makefile test_basic

# 仿真器选择
SIM ?= xcelium

# UVM 测试名
TEST ?= test_flashattn_complete

# 源文件
RTL_SRC = \
    ../rtl/flashattn_pkg.sv \
    ../rtl/flashattn_top.sv \
    ../rtl/pipelined_exp_fixed.sv \
    ../rtl/online_softmax_exact.sv \
    ../rtl/gemm0_dot_product.sv \
    ../rtl/gemm1_pv_multiply.sv \
    ../rtl/causal_mask_unit.sv \
    ../rtl/axil_csr.sv \
    ../rtl/axi4_dma_engine.sv \
    ../rtl/tile_prefetcher.sv \
    ../rtl/quantize_q8p8.sv \
    ../rtl/perf_counters.sv \
    ../rtl/block_scale_finder.sv

TB_SRC = \
    axil_if.sv \
    axi4_mem_if.sv \
    axil_transfer.sv \
    axi4_mem_trans.sv \
    flashattn_config.sv \
    axil_driver.sv \
    axil_monitor.sv \
    axil_sequencer.sv \
    axil_agent.sv \
    axi4_mem_driver.sv \
    axi4_mem_monitor.sv \
    axi4_mem_agent.sv \
    flashattn_base_seq.sv \
    flashattn_reg_rw_seq.sv \
    flashattn_rand_seq.sv \
    flashattn_causal_corner_seq.sv \
    flashattn_scoreboard.sv \
    flashattn_coverage.sv \
    flashattn_env.sv \
    test_flashattn_basic.sv \
    test_flashattn_random.sv \
    test_flashattn_complete.sv \
    test_top.sv

# =================================================================
# Cadence Xcelium 命令
# =================================================================
xrun:
	xrun -64bit \
		-uvm \
		-uvmhome CDNS-1.2 \
		+UVM_TESTNAME=$(TEST) \
		+UVM_VERBOSITY=UVM_MEDIUM \
		-timescale 1ns/1ps \
		-access +rwc \
		$(addprefix -v, $(RTL_SRC)) \
		$(TB_SRC)

# GUI 模式
xrun_gui:
	xrun -64bit \
		-uvm \
		-uvmhome CDNS-1.2 \
		+UVM_TESTNAME=$(TEST) \
		-timescale 1ns/1ps \
		-access +rwc \
		-gui \
		$(addprefix -v, $(RTL_SRC)) \
		$(TB_SRC)

# =================================================================
# 便捷 target
# =================================================================
.PHONY: test_basic test_random test_complete xrun_gui clean

test_basic:
	$(MAKE) xrun TEST=test_flashattn_basic

test_random:
	$(MAKE) xrun TEST=test_flashattn_random

test_complete:
	$(MAKE) xrun TEST=test_flashattn_complete

clean:
	rm -rf xcelium.d waves.shm *.log *.vcd xrun.*
