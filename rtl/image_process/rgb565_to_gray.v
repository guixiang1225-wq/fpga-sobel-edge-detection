// Combinational RGB565 to 8-bit grayscale; no additional clock latency.
module rgb565_to_gray (
    input  wire [15:0] rgb565,
    output wire [7:0]  gray8
);
    wire [7:0] r8;
    wire [7:0] g8;
    wire [7:0] b8;
    wire [15:0] gray_sum;

    // Expand each channel to 8 bits by repeating its most significant bits.
    assign r8 = {rgb565[15:11], rgb565[15:13]};
    assign g8 = {rgb565[10:5],  rgb565[10:9]};
    assign b8 = {rgb565[4:0],   rgb565[4:2]};

    // Y = round((77*R + 150*G + 29*B) / 256).
    // Maximum sum is 65408, which fits in 16 unsigned bits.
    assign gray_sum = r8 * 16'd77 + g8 * 16'd150
                    + b8 * 16'd29 + 16'd128;
    assign gray8 = gray_sum[15:8];
endmodule
