// Everything stays in the 33 MHz pixel domain: no multi-bit threshold CDC.
module sobel_threshold_keys #(
    parameter DEBOUNCE_CYCLES=660000,
    parameter [10:0] INITIAL_THRESHOLD=11'd128,
    parameter [10:0] MAX_THRESHOLD=11'd2040
)(
    input wire clk,rst_n,frame_prepare,key_up_n,key_down_n,
    output reg [10:0] threshold_requested,
    output reg [10:0] threshold_active
);
    wire up_pulse,down_pulse;
    reg [10:0] next_threshold;
    button_press_pulse #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_up (
        .clk(clk),.rst_n(rst_n),.key_n(key_up_n),.press_pulse(up_pulse)
    );
    button_press_pulse #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_down (
        .clk(clk),.rst_n(rst_n),.key_n(key_down_n),.press_pulse(down_pulse)
    );
    always @* begin
        next_threshold=threshold_requested;
        case ({up_pulse,down_pulse})
            2'b10: next_threshold=(threshold_requested>=MAX_THRESHOLD-11'd8) ?
                       MAX_THRESHOLD : threshold_requested+11'd8;
            2'b01: next_threshold=(threshold_requested<=11'd8) ?
                       11'd0 : threshold_requested-11'd8;
            default: next_threshold=threshold_requested;
        endcase
    end
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            threshold_requested<=INITIAL_THRESHOLD;
            threshold_active<=INITIAL_THRESHOLD;
        end else begin
            threshold_requested<=next_threshold;
            if (frame_prepare) threshold_active<=next_threshold;
        end
endmodule
