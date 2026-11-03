`timescale 1ns/1ps
module compare_case #(parameter LENGTH = 256, parameter ID = 0)(output reg done = 0);
    reg ctrl_clk = 0, wr_clk = 0, rd_clk = 0;
    always #4 ctrl_clk = ~ctrl_clk;
    always #7 wr_clk = ~wr_clk;
    always #11 rd_clk = ~rd_clk;
    reg reset_n = 0;
    reg wr_load = 1, rd_load = 1;
    reg enable = 0;
    reg [15:0] input_data = 16'h1234;
    reg [15:0] memory_pattern = 16'hace1;
    integer producer_ticks = 0, consumer_ticks = 0;
    wire [15:0] old_rd_data, new_rd_data;
    wire old_full, new_full, old_empty, new_empty;
    wire [15:0] old_wr_use, new_wr_use, old_rd_use, new_rd_use;
    wire [11:0] old_sa, new_sa;
    wire [1:0] old_ba, new_ba, old_cs, new_cs, old_dqm, new_dqm;
    wire old_cke, new_cke, old_ras, new_ras, old_cas, new_cas, old_we, new_we;
    tri [15:0] old_dq, new_dq;
    localparam [9:0] TRANSFER_LENGTH = LENGTH;
    localparam [23:0] BASE = 24'd512;
    localparam [23:0] LIMIT = BASE + ((LENGTH == 0) ? 256 : LENGTH * 3);
    wire wr_req = enable && !wr_load && !old_full && producer_ticks % 3 != 0;
    wire rd_req = enable && !rd_load && !old_empty && consumer_ticks % 3 == 0;
    // Equal external read-data stimulus, intentionally not a physical SDRAM model.
    assign old_dq = old_dut.oe ? 16'hzzzz : memory_pattern;
    assign new_dq = new_dut.oe ? 16'hzzzz : memory_pattern;

    Sdram_Control_4Port old_dut(
        .CTRL_CLK(ctrl_clk), .RESET_N(reset_n),
        .WR1_DATA(input_data), .WR1(wr_req), .WR1_ADDR(BASE), .WR1_MAX_ADDR(LIMIT),
        .WR1_LENGTH(TRANSFER_LENGTH), .WR1_LOAD(wr_load), .WR1_CLK(wr_clk),
        .WR1_FULL(old_full), .WR1_USE(old_wr_use),
        .WR2_DATA(16'd0), .WR2(1'b0), .WR2_ADDR(24'd0), .WR2_MAX_ADDR(24'd0),
        .WR2_LENGTH(9'd8), .WR2_LOAD(1'b0), .WR2_CLK(1'b0), .WR2_FULL(), .WR2_USE(),
        .RD1_DATA(old_rd_data), .RD1(rd_req), .RD1_ADDR(BASE), .RD1_MAX_ADDR(LIMIT),
        .RD1_LENGTH(TRANSFER_LENGTH), .RD1_LOAD(rd_load), .RD1_CLK(rd_clk),
        .RD1_EMPTY(old_empty), .RD1_USE(old_rd_use),
        .RD2_DATA(), .RD2(1'b0), .RD2_ADDR(24'd0), .RD2_MAX_ADDR(24'd0),
        .RD2_LENGTH(9'd0), .RD2_LOAD(1'b0), .RD2_CLK(1'b0), .RD2_EMPTY(), .RD2_USE(),
        .SA(old_sa), .BA(old_ba), .CS_N(old_cs), .CKE(old_cke),
        .RAS_N(old_ras), .CAS_N(old_cas), .WE_N(old_we), .DQ(old_dq), .DQM(old_dqm)
    );
    Sdram_Control_2Port new_dut(
        .CTRL_CLK(ctrl_clk), .RESET_N(reset_n),
        .WR1_DATA(input_data), .WR1(wr_req), .WR1_ADDR(BASE), .WR1_MAX_ADDR(LIMIT),
        .WR1_LENGTH(TRANSFER_LENGTH), .WR1_LOAD(wr_load), .WR1_CLK(wr_clk),
        .WR1_FULL(new_full), .WR1_USE(new_wr_use),
        .RD1_DATA(new_rd_data), .RD1(rd_req), .RD1_ADDR(BASE), .RD1_MAX_ADDR(LIMIT),
        .RD1_LENGTH(TRANSFER_LENGTH), .RD1_LOAD(rd_load), .RD1_CLK(rd_clk),
        .RD1_EMPTY(new_empty), .RD1_USE(new_rd_use),
        .SA(new_sa), .BA(new_ba), .CS_N(new_cs), .CKE(new_cke),
        .RAS_N(new_ras), .CAS_N(new_cas), .WE_N(new_we), .DQ(new_dq), .DQM(new_dqm)
    );
    always @(negedge wr_clk) begin
        producer_ticks = producer_ticks + 1;
        input_data = input_data + 16'h31;
    end
    always @(negedge rd_clk) consumer_ticks = consumer_ticks + 1;
    always @(posedge ctrl_clk)
        memory_pattern <= {memory_pattern[14:0], memory_pattern[15]^memory_pattern[13]^memory_pattern[12]^memory_pattern[10]};

    integer checked_cycles = 0, writes_done = 0, reads_done = 0;
    integer write_words = 0, read_words = 0, refreshes = 0;
    integer write_wraps = 0, read_wraps = 0, priority_checks = 0;
    integer burst_write_words = 0, burst_read_words = 0;
    reg [23:0] previous_wr_address = BASE, previous_rd_address = BASE;
    reg previous_wr_done = 0, previous_rd_done = 0;
    reg expected_read_priority = 0;
    reg previous_active_write = 0, previous_active_read = 0;
    always @(negedge ctrl_clk) begin
        if (reset_n) begin
            checked_cycles = checked_cycles + 1;
            if (ID == 0 && checked_cycles % 10000 == 0)
                $display("Progress: %0d comparison cycles, time=%t", checked_cycles, $time);
            if ({old_sa,old_ba,old_cs,old_cke,old_ras,old_cas,old_we,old_dqm} !==
                {new_sa,new_ba,new_cs,new_cke,new_ras,new_cas,new_we,new_dqm})
                $fatal(1, "case %0d: SDRAM command/address mismatch at %t", ID, $time);
            if ({old_full,old_empty,old_wr_use,old_rd_use} !== {new_full,new_empty,new_wr_use,new_rd_use})
                $fatal(1, "case %0d: FIFO flags/count mismatch at %t", ID, $time);
            if (!old_empty && old_rd_data !== new_rd_data)
                $fatal(1, "case %0d: consumer data mismatch at %t", ID, $time);
            if ({old_dut.ST,old_dut.CMD,old_dut.mADDR,old_dut.mLENGTH,old_dut.IN_REQ,
                 old_dut.OUT_VALID,old_dut.mWR_DONE,old_dut.mRD_DONE,
                 old_dut.rWR1_ADDR,old_dut.rRD1_ADDR,old_dut.oe,
                 old_dut.WR_MASK[0],old_dut.RD_MASK[0]} !==
                {new_dut.ST,new_dut.CMD,new_dut.mADDR,new_dut.mLENGTH,new_dut.IN_REQ,
                 new_dut.OUT_VALID,new_dut.mWR_DONE,new_dut.mRD_DONE,
                 new_dut.rWR1_ADDR,new_dut.rRD1_ADDR,new_dut.oe,
                 new_dut.WR_MASK,new_dut.RD_MASK})
                $fatal(1, "case %0d: controller state mismatch at %t", ID, $time);
            if (new_dut.oe && new_dqm != 2'b11 && old_dq !== new_dq)
                $fatal(1, "case %0d: SDRAM write data mismatch at %t", ID, $time);
            if (expected_read_priority && !wr_load && !rd_load) begin
                if (!new_dut.mRD || new_dut.mWR)
                    $fatal(1, "case %0d: read priority changed", ID);
                priority_checks = priority_checks + 1;
            end
            expected_read_priority = !new_dut.mWR && !new_dut.mRD && new_dut.ST == 0 &&
                !new_dut.WR_MASK && !new_dut.RD_MASK && !wr_load && !rd_load &&
                new_dut.read_side_fifo_wusedw1 < TRANSFER_LENGTH &&
                new_dut.write_side_fifo_rusedw1 >= TRANSFER_LENGTH && TRANSFER_LENGTH != 0;
            if (new_dut.Write && !previous_active_write) burst_write_words = 0;
            if (new_dut.Read && !previous_active_read) burst_read_words = 0;
            if (new_dut.IN_REQ && new_dut.WR_MASK) begin
                write_words = write_words + 1;
                burst_write_words = burst_write_words + 1;
            end
            if (new_dut.OUT_VALID && new_dut.RD_MASK) begin
                read_words = read_words + 1;
                burst_read_words = burst_read_words + 1;
            end
            if (new_dut.mWR_DONE && !previous_wr_done) begin
                writes_done = writes_done + 1;
                if (burst_write_words != LENGTH)
                    $fatal(1, "case %0d: write count %0d != %0d", ID, burst_write_words, LENGTH);
            end
            if (new_dut.mRD_DONE && !previous_rd_done) begin
                reads_done = reads_done + 1;
                if (burst_read_words != LENGTH)
                    $fatal(1, "case %0d: read count %0d != %0d", ID, burst_read_words, LENGTH);
            end
            if (new_dut.rWR1_ADDR < previous_wr_address) write_wraps = write_wraps + 1;
            if (new_dut.rRD1_ADDR < previous_rd_address) read_wraps = read_wraps + 1;
            if (new_dut.ref_ack) refreshes = refreshes + 1;
            previous_wr_done = new_dut.mWR_DONE;
            previous_rd_done = new_dut.mRD_DONE;
            previous_wr_address = new_dut.rWR1_ADDR;
            previous_rd_address = new_dut.rRD1_ADDR;
            previous_active_write = new_dut.Write;
            previous_active_read = new_dut.Read;
        end else begin
            expected_read_priority = 0;
            previous_wr_done = 0;
            previous_rd_done = 0;
            previous_active_write = 0;
            previous_active_read = 0;
        end
    end
    task reset_controllers;
        begin
            @(negedge ctrl_clk);
            reset_n = 0; enable = 0; wr_load = 1; rd_load = 1;
            repeat (10) @(negedge ctrl_clk);
            reset_n = 1;
            // Preserve the original power-up delay instead of overriding parameters.
            repeat (24500) @(negedge ctrl_clk);
            #1; wr_load = 0; rd_load = 0; enable = 1;
        end
    endtask
    initial begin
        $display("Starting equivalence case %0d, length=%0d", ID, LENGTH);
        reset_controllers();
        repeat (30000) @(negedge ctrl_clk);
        // Exercise original LOAD semantics, including clearing during traffic.
        #1; wr_load = 1; rd_load = 1;
        repeat (20) @(negedge ctrl_clk);
        #1; wr_load = 0; rd_load = 0;
        repeat (10000) @(negedge ctrl_clk);
        reset_controllers();
        repeat (30000) @(negedge ctrl_clk);
        #2;
        if (LENGTH != 0 && (writes_done < 5 || reads_done < 5 || write_wraps == 0 || read_wraps == 0))
            $fatal(1, "case %0d: insufficient read/write/wrap coverage", ID);
        if (LENGTH == 0 && (writes_done != 0 || reads_done != 0))
            $fatal(1, "zero-length case unexpectedly transferred data");
        if (refreshes < 5) $fatal(1, "case %0d: insufficient refresh coverage", ID);
        $display("PASS case=%0d length=%0d cycles=%0d writes=%0d reads=%0d write_words=%0d read_words=%0d write_wraps=%0d read_wraps=%0d refreshes=%0d priority_checks=%0d",
                 ID,LENGTH,checked_cycles,writes_done,reads_done,write_words,read_words,
                 write_wraps,read_wraps,refreshes,priority_checks);
        done = 1;
    end
endmodule

module tb_equivalence;
    wire [3:0] done;
    compare_case #(.LENGTH(256), .ID(0)) main_case(done[0]);
    compare_case #(.LENGTH(64), .ID(1)) medium_case(done[1]);
    compare_case #(.LENGTH(8), .ID(2)) short_case(done[2]);
    compare_case #(.LENGTH(0), .ID(3)) disabled_case(done[3]);
    initial begin
        wait (&done);
        $display("PASS: all four old/new controller equivalence cases completed.");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "Test timed out");
    end
endmodule
