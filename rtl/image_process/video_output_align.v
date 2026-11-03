// Metadata RAM delay: a tap_distance=D+1 gives C -> C+D post-edge.
module video_output_align #(
    parameter IMAGE_WIDTH=800, IMAGE_HEIGHT=480,
    parameter CENTER_TO_RESULT=1060
)(
    input wire clk,rst_n,
    input wire src_hs,src_vs,src_de,
    input wire [9:0] src_x,
    input wire [8:0] src_y,
    input wire [7:0] edge8,
    input wire edge_valid, fault,
    output wire [15:0] tft_rgb,
    output wire tft_hs,tft_vs,tft_de,
    output wire [9:0] out_x,
    output wire [8:0] out_y
);
    wire [21:0] delayed;
    altshift_taps #(
        .intended_device_family("Cyclone IV E"),
        .lpm_type("altshift_taps"),
        .number_of_taps(1),.tap_distance(CENTER_TO_RESULT+1),
        .width(22),.power_up_state("CLEARED")
    ) u_metadata (
        .clock(clk),.clken(1'b1),.aclr(!rst_n),
        .shiftin({src_hs,src_vs,src_de,src_x,src_y}),
        .taps(delayed),.shiftout()
    );
    assign {tft_hs,tft_vs,tft_de,out_x,out_y}=delayed;
    wire border=(out_x==0 || out_x==IMAGE_WIDTH-1 ||
                 out_y==0 || out_y==IMAGE_HEIGHT-1);
    assign tft_rgb=(rst_n && tft_de && !border && edge_valid && !fault) ?
                    {edge8[7:3],edge8[7:2],edge8[7:3]} : 16'd0;
endmodule
