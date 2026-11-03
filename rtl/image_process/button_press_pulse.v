// Active-low pushbutton. Two-stage synchronizer and stable-level debounce.
// A held button emits one pulse. Release must debounce before another press.
module button_press_pulse #(parameter DEBOUNCE_CYCLES=660000)(
    input wire clk,rst_n,key_n,
    output reg press_pulse
);
    localparam COUNT_WIDTH=(DEBOUNCE_CYCLES<=1)?1:$clog2(DEBOUNCE_CYCLES);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg sync_meta,sync_key;
    reg stable_key;
    reg [COUNT_WIDTH-1:0] count;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin sync_meta<=1'b1; sync_key<=1'b1; end
        else begin sync_meta<=key_n; sync_key<=sync_meta; end
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin count<=0;stable_key<=1'b1;press_pulse<=0;end
        else begin
            press_pulse<=0;
            if (sync_key==stable_key) count<=0;
            else if (count==DEBOUNCE_CYCLES-1) begin
                count<=0;stable_key<=sync_key;
                if (!sync_key) press_pulse<=1;
            end else count<=count+1'b1;
        end
endmodule
