// Quartus 13 ALTSHIFT_TAPS: two historical rows; current row bypasses IP.
module gray_line_shift #(parameter LINE_PIXELS=800)(
    input wire clock, clken, aclr,
    input wire [7:0] shiftin,
    output wire [15:0] taps
);
    altshift_taps #(
        .intended_device_family("Cyclone IV E"),
        .lpm_type("altshift_taps"),
        .number_of_taps(2), .tap_distance(LINE_PIXELS), .width(8),
        .power_up_state("CLEARED")
    ) u_shift (
        .clock(clock), .clken(clken), .aclr(aclr),
        .shiftin(shiftin), .taps(taps), .shiftout()
    );
endmodule
