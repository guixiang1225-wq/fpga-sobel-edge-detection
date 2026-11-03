// No extra output registers: consume pre-edge taps with current gray_in.
module gray_line_buffer #(parameter LINE_PIXELS=800)(
    input wire clk, rst_n, pixel_en,
    input wire [7:0] gray_in,
    output wire [7:0] row1, row2
);
    wire [15:0] taps;
    gray_line_shift #(.LINE_PIXELS(LINE_PIXELS)) u_ip (
        .clock(clk), .clken(pixel_en), .aclr(!rst_n),
        .shiftin(gray_in), .taps(taps)
    );
    assign row1=taps[7:0];
    assign row2=taps[15:8];
endmodule
