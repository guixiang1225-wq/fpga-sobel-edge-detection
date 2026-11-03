// Matrix and Sobel merged. W registers + A1/A2/A3 arithmetic stages.
module sobel_filter #(
    parameter IMAGE_WIDTH=800, IMAGE_HEIGHT=480,
    parameter BINARY_MODE=1,
    parameter GAIN_SHIFT=2
)(
    input wire clk, rst_n, frame_prepare, in_valid,
    input wire [9:0] in_x,
    input wire [8:0] in_y,
    input wire [7:0] gray_in, row1, row2,
    input wire [10:0] threshold,
    output reg [7:0] edge8,
    output reg edge_valid,
    output reg [9:0] edge_x,
    output reg [8:0] edge_y
);
    reg [7:0] p11,p12,p13,p21,p22,p23,p31,p32,p33;
    reg win_valid,v1,v2;
    reg [9:0] xw,x1,x2;
    reg [8:0] yw,y1,y2;
    reg signed [10:0] gx_reg,gy_reg;
    reg [10:0] magnitude_reg;
    wire signed [10:0] s11=$signed({3'b000,p11});
    wire signed [10:0] s12=$signed({3'b000,p12});
    wire signed [10:0] s13=$signed({3'b000,p13});
    wire signed [10:0] s21=$signed({3'b000,p21});
    wire signed [10:0] s23=$signed({3'b000,p23});
    wire signed [10:0] s31=$signed({3'b000,p31});
    wire signed [10:0] s32=$signed({3'b000,p32});
    wire signed [10:0] s33=$signed({3'b000,p33});
    wire [10:0] ax=gx_reg[10] ? -gx_reg : gx_reg;
    wire [10:0] ay=gy_reg[10] ? -gy_reg : gy_reg;
    wire [10:0] scaled=magnitude_reg >> GAIN_SHIFT;
    // Old RAM contents at a new frame are invalid until y>=2.
    // The RAM itself need not be cleared each frame.
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            {p11,p12,p13,p21,p22,p23,p31,p32,p33}<=72'd0;
            win_valid<=0; xw<=0; yw<=0;
        end else begin
            win_valid<=in_valid && in_x>=2 && in_y>=2;
            if (frame_prepare) begin
                {p11,p12,p13,p21,p22,p23,p31,p32,p33}<=72'd0;
                win_valid<=0;
            end else if (in_valid) begin
                {p11,p12,p13}<={p12,p13,row2};
                {p21,p22,p23}<={p22,p23,row1};
                {p31,p32,p33}<={p32,p33,gray_in};
                xw<=in_x-1'b1; yw<=in_y-1'b1;
            end
        end
    // Run on every pixel clock, including blanking: drain line-tail results.
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            gx_reg<=0; gy_reg<=0; magnitude_reg<=0; edge8<=0;
            v1<=0; v2<=0; edge_valid<=0;
            x1<=0; x2<=0; edge_x<=0; y1<=0; y2<=0; edge_y<=0;
        end else begin
            gx_reg<=s13+(s23<<<1)+s33-s11-(s21<<<1)-s31;
            gy_reg<=s31+(s32<<<1)+s33-s11-(s12<<<1)-s13;
            magnitude_reg<=ax+ay;
            if (BINARY_MODE)
                edge8<=(magnitude_reg>=threshold)?8'hff:8'h00;
            else
                edge8<=(scaled>11'd255)?8'hff:scaled[7:0];
            v1<=win_valid; v2<=v1; edge_valid<=v2;
            x1<=xw; x2<=x1; edge_x<=x2;
            y1<=yw; y2<=y1; edge_y<=y2;
        end
endmodule
