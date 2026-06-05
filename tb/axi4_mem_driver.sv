// ==========================================================================
// axi4_mem_driver — AXI4 Slave 内存模型 (模拟 DDR)
// ==========================================================================
// 功能: 模拟外部 DDR 内存, 响应 DUT AXI4-Master 的读写请求
//       - 读请求: 从内部存储数组返回数据
//       - 写请求: 将数据存入内部存储数组
//
// UVM 概念对照:
//   这个 Driver 比较特殊 —— 它不是驱动 DUT, 而是模拟 DUT 的"对端"
//   所以它是 AXI4 Slave (被 DUT Master 驱动)
//   内部维护一个 memory 数组来模拟 DDR 存储
// ==========================================================================

`ifndef AXI4_MEM_DRIVER_SV
`define AXI4_MEM_DRIVER_SV

class axi4_mem_driver extends uvm_driver #(axi4_mem_trans);

    `uvm_component_utils(axi4_mem_driver)

    virtual axi4_mem_if.slave vif;

    // ---- 内部 DDR 模型: 64-bit 数组, 深度 = 64KB (容纳 Q+K+V+O) ----
    localparam int MEM_DEPTH = 8192;  // 8192 × 8 bytes = 64 KB
    bit [63:0] mem [MEM_DEPTH];

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_mem_if.slave)::get(this, "", "axi4_vif", vif))
            `uvm_fatal("MEM_DRV", "Virtual interface not found")
    endfunction

    // ==================================================================
    // run_phase: 并行处理读和写请求
    // ==================================================================
    task run_phase(uvm_phase phase);
        fork
            handle_reads();
            handle_writes();
        join
    endtask

    // ---- 处理 AXI4 读请求 ----
    task handle_reads();
        forever begin
            @(posedge vif.clk);
            if (vif.arvalid) begin
                vif.arready <= 1'b1;
                @(posedge vif.clk);
                vif.arready <= 1'b0;

                // 计算地址索引 (64-bit aligned)
                int addr_idx = vif.araddr[15:3];  // /8 bytes = 64-bit index
                int burst_beats = vif.arlen + 1;

                for (int i = 0; i < burst_beats; i++) begin
                    vif.rvalid <= 1'b1;
                    vif.rdata  <= mem[addr_idx + i];
                    vif.rresp  <= 2'b00;  // OKAY
                    vif.rlast  <= (i == burst_beats - 1);
                    vif.rid    <= vif.arid;

                    @(posedge vif.clk);
                    while (!vif.rready) @(posedge vif.clk);
                end
                vif.rvalid <= 1'b0;
            end
        end
    endtask

    // ---- 处理 AXI4 写请求 ----
    task handle_writes();
        forever begin
            @(posedge vif.clk);
            if (vif.awvalid && vif.wvalid) begin
                int addr_idx = vif.awaddr[15:3];
                int burst_beats = vif.awlen + 1;

                vif.awready <= 1'b1;
                vif.wready  <= 1'b1;

                for (int i = 0; i < burst_beats; i++) begin
                    @(posedge vif.clk);
                    mem[addr_idx + i] = vif.wdata;
                end
                vif.awready <= 1'b0;
                vif.wready  <= 1'b0;

                // 写响应
                vif.bvalid <= 1'b1;
                vif.bresp  <= 2'b00;
                vif.bid    <= vif.awid;
                @(posedge vif.clk);
                while (!vif.bready) @(posedge vif.clk);
                vif.bvalid <= 1'b0;
            end
        end
    endtask

    // ==================================================================
    // 外部方法: 将 Q/K/V 数据预加载到内存 (testbench 调用)
    // ==================================================================
    function void load_matrix(input bit [63:0] base_addr,
                              input bit [15:0] matrix[][],
                              input int rows, input int cols);
        int addr_idx = base_addr[15:3];
        for (int r = 0; r < rows; r++) begin
            for (int c = 0; c < cols; c += 4) begin  // 4 × Q8.8 = 64-bit
                bit [15:0] e0, e1, e2, e3;
                e0 = (c+0 < cols) ? matrix[r][c+0] : 16'd0;
                e1 = (c+1 < cols) ? matrix[r][c+1] : 16'd0;
                e2 = (c+2 < cols) ? matrix[r][c+2] : 16'd0;
                e3 = (c+3 < cols) ? matrix[r][c+3] : 16'd0;
                mem[addr_idx] = {e3, e2, e1, e0};
                addr_idx++;
            end
        end
    endfunction

    // 读出 O 矩阵 (用于 Scoreboard 对比)
    function void read_matrix(input bit [63:0] base_addr,
                              output bit [15:0] matrix[][],
                              input int rows, input int cols);
        int addr_idx = base_addr[15:3];
        matrix = new[rows];
        for (int r = 0; r < rows; r++) begin
            matrix[r] = new[cols];
            for (int c = 0; c < cols; c += 4) begin
                bit [63:0] beat = mem[addr_idx];
                for (int i = 0; i < 4 && (c+i) < cols; i++)
                    matrix[r][c+i] = beat[(i+1)*16-1 -: 16];
                addr_idx++;
            end
        end
    endfunction

endclass

`endif // AXI4_MEM_DRIVER_SV
