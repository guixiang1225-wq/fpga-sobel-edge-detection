// Complete read-side pixel pipeline. Original raw DataReq never uses delayed DE.
module sobel_video_pipeline #(
    parameter IMAGE_WIDTH=800, IMAGE_HEIGHT=480,
    parameter H_SYNC=128,H_BACK=88,H_FRONT=40,
    parameter V_SYNC=2,V_BACK=33,V_FRONT=10,
    parameter BINARY_MODE=1, parameter [10:0] THRESHOLD=11'd128,
    parameter GAIN_SHIFT=2, parameter BUTTON_DEBOUNCE_CYCLES=660000
)(
    input wire clk,rst_n,
    input wire key_up_n,key_down_n,
    input wire [15:0] rgb565,
    input wire fifo_empty,
    input wire [9:0] fifo_used, // RD1 read-clock-domain occupancy, 0..512
    output wire data_req,
    output wire [15:0] tft_rgb,
    output wire tft_hs,tft_vs,tft_de,
    output reg underflow_sticky
);
    localparam H_TOTAL=H_SYNC+H_BACK+IMAGE_WIDTH+H_FRONT;
    localparam CENTER_TO_RESULT=H_TOTAL+4;
    wire sh,sv,sd,prep;
    wire [9:0] sx,ex,ox;
    wire [8:0] sy,ey,oy;
    wire [7:0] gray8,row1,row2,edge8;
    wire ev;
    wire [10:0] threshold_requested,threshold_active;
    sobel_threshold_keys #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES),.INITIAL_THRESHOLD(THRESHOLD)
    ) u_keys (
        .clk(clk),.rst_n(rst_n),.frame_prepare(prep),
        .key_up_n(key_up_n),.key_down_n(key_down_n),
        .threshold_requested(threshold_requested),.threshold_active(threshold_active)
    );
    tft_timing_gen #(
        .IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_FRONT(H_FRONT),
        .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_FRONT(V_FRONT)
    ) u_timing (
        .clk(clk),.rst_n(rst_n),.src_hs(sh),.src_vs(sv),.src_de(sd),
        .src_x(sx),.src_y(sy),.frame_prepare(prep)
    );
    // The SDRAM controller cannot prefetch while camera WR1_LOAD is high.
    // Keep address zero queued until a complete burst is available, then
    // consume pixel zero at the next raw frame boundary. Do not pause a line
    // or start in the middle of an active frame.
    reg stream_started;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) stream_started<=1'b0;
        else if (prep && !fifo_empty && fifo_used>=10'd256)
            stream_started<=1'b1;
    assign data_req=sd && stream_started;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) underflow_sticky<=0;
        else if (data_req && fifo_empty) underflow_sticky<=1;
    // Startup empty is expected; only a running-stream underrun is a fault.
    // Preserve pixel slots on a running fault; suppress the image until reset.
    // Silently skipping a sample would corrupt all subsequent line positions.
    rgb565_to_gray u_gray (.rgb565(rgb565),.gray8(gray8));
    gray_line_buffer #(.LINE_PIXELS(IMAGE_WIDTH)) u_lines (
        .clk(clk),.rst_n(rst_n),.pixel_en(data_req),
        .gray_in(fifo_empty ? 8'd0 : gray8),.row1(row1),.row2(row2)
    );
    sobel_filter #(
        .IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .BINARY_MODE(BINARY_MODE),.GAIN_SHIFT(GAIN_SHIFT)
    ) u_sobel (
        .clk(clk),.rst_n(rst_n),.frame_prepare(prep),.in_valid(data_req),
        .in_x(sx),.in_y(sy),.gray_in(fifo_empty ? 8'd0 : gray8),
        .row1(row1),.row2(row2),.threshold(threshold_active),.edge8(edge8),.edge_valid(ev),
        .edge_x(ex),.edge_y(ey)
    );
    video_output_align #(
        .IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .CENTER_TO_RESULT(CENTER_TO_RESULT)
    ) u_output (
        .clk(clk),.rst_n(rst_n),.src_hs(sh),.src_vs(sv),.src_de(sd),
        .src_x(sx),.src_y(sy),.edge8(edge8),.edge_valid(ev),
        .fault(underflow_sticky),.tft_rgb(tft_rgb),
        .tft_hs(tft_hs),.tft_vs(tft_vs),.tft_de(tft_de),
        .out_x(ox),.out_y(oy)
    );
endmodule
