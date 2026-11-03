`timescale 1ns/1ps
// Simulation-only FIFO substitute for old/new controller comparison.
// This is NOT a replacement for altera_mf.dcfifo in synthesis, CDC or timing QA.
module dcfifo #(
    parameter add_usedw_msb_bit = "ON",
    parameter intended_device_family = "Cyclone IV E",
    parameter lpm_hint = "RAM_BLOCK_TYPE=M9K",
    parameter lpm_numwords = 512,
    parameter lpm_showahead = "OFF",
    parameter lpm_type = "dcfifo",
    parameter lpm_width = 16,
    parameter lpm_widthu = 10,
    parameter overflow_checking = "ON",
    parameter rdsync_delaypipe = 4,
    parameter read_aclr_synch = "OFF",
    parameter underflow_checking = "ON",
    parameter use_eab = "ON",
    parameter write_aclr_synch = "OFF",
    parameter wrsync_delaypipe = 4
)(
    input rdclk, wrclk, wrreq, aclr, rdreq,
    input [lpm_width-1:0] data,
    output wrfull, rdempty, rdfull, wrempty,
    output [lpm_width-1:0] q,
    output [lpm_widthu-1:0] wrusedw, rdusedw
);
    reg [lpm_width-1:0] memory [0:lpm_numwords-1];
    reg [lpm_width-1:0] registered_q = 0;
    integer writes = 0;
    integer reads = 0;
    wire [31:0] used = writes - reads;
    assign wrusedw = used[lpm_widthu-1:0];
    assign rdusedw = used[lpm_widthu-1:0];
    assign wrfull = (used >= lpm_numwords);
    assign rdfull = wrfull;
    assign rdempty = (used == 0);
    assign wrempty = rdempty;
    assign q = (lpm_showahead == "ON") ? memory[reads % lpm_numwords] : registered_q;
    always @(posedge wrclk or posedge aclr) begin
        if (aclr) writes <= 0;
        else if (wrreq && !wrfull) begin
            memory[writes % lpm_numwords] <= data;
            writes <= writes + 1;
        end
    end
    always @(posedge rdclk or posedge aclr) begin
        if (aclr) begin
            reads <= 0;
            registered_q <= 0;
        end else if (rdreq && !rdempty) begin
            registered_q <= memory[reads % lpm_numwords];
            reads <= reads + 1;
        end
    end
endmodule
