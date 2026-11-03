// Raw raster and show-ahead FIFO consumption use the same pre-edge pixel.
module tft_timing_gen #(
    parameter IMAGE_WIDTH=800, IMAGE_HEIGHT=480,
    parameter H_SYNC=128, H_BACK=88, H_FRONT=40,
    parameter V_SYNC=2, V_BACK=33, V_FRONT=10
)(
    input wire clk, rst_n,
    output wire src_hs, src_vs, src_de,
    output wire [9:0] src_x,
    output wire [8:0] src_y,
    output wire frame_prepare
);
    localparam H_TOTAL=H_SYNC+H_BACK+IMAGE_WIDTH+H_FRONT;
    localparam V_TOTAL=V_SYNC+V_BACK+IMAGE_HEIGHT+V_FRONT;
    reg [11:0] hcount, vcount;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin hcount<=0; vcount<=0; end
        else if (hcount==H_TOTAL-1) begin
            hcount<=0;
            if (vcount==V_TOTAL-1) vcount<=0;
            else vcount<=vcount+1'b1;
        end else hcount<=hcount+1'b1;
    assign src_hs=(hcount>=H_SYNC);
    assign src_vs=(vcount>=V_SYNC);
    assign src_de=rst_n && hcount>=H_SYNC+H_BACK &&
                  hcount<H_SYNC+H_BACK+IMAGE_WIDTH &&
                  vcount>=V_SYNC+V_BACK &&
                  vcount<V_SYNC+V_BACK+IMAGE_HEIGHT;
    wire [11:0] x_offset=hcount-(H_SYNC+H_BACK);
    wire [11:0] y_offset=vcount-(V_SYNC+V_BACK);
    assign src_x=src_de ? x_offset[9:0] : 10'd0;
    assign src_y=src_de ? y_offset[8:0] : 9'd0;
    assign frame_prepare=(hcount==0 && vcount==0);
endmodule
