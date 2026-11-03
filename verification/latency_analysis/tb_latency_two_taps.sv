`timescale 1ns/1ps
module tb_latency_two_taps;
    reg clk=0;
    always #5 clk=~clk;
    reg clken=0;
    reg [31:0] pixel_tag=0;
    wire [63:0] taps;
    wire [31:0] unused_shiftout;
    reg [31:0] p11=0,p12=0,p13=0,p21=0,p22=0,p23=0,p31=0,p32=0,p33=0;
    reg [31:0] grad_tag=0, magnitude_tag=0, result_tag=0, display_tag=0;
    reg [4:0] valid_pipe=0;
    integer tick=-1;
    integer drive_tick;
    integer x=0, y=0;
    integer checks=0;
    altshift_taps #(.number_of_taps(2),.tap_distance(800),.width(32)) ip (
        .clock(clk),.clken(clken),.aclr(1'b0),.shiftin(pixel_tag),
        .shiftout(unused_shiftout),.taps(taps)
    );
    always @(posedge clk) begin
        tick=tick+1;
        if(clken) begin
            p11<=p12; p12<=p13; p13<=taps[63:32];
            p21<=p22; p22<=p23; p23<=taps[31:0];
            p31<=p32; p32<=p33; p33<=pixel_tag;
        end
        grad_tag<=p22;
        magnitude_tag<=grad_tag;
        result_tag<=magnitude_tag;
        display_tag<=result_tag;
        valid_pipe<={valid_pipe[3:0],(clken && y>=2 && x>=2)};
        #1;
        if(clken && y>=2 && x>=2 && tick-p22 != 1057)
            $fatal(1,"Window center latency mismatch");
        if(valid_pipe[3]) begin
            if(tick-result_tag != 1060)
                $fatal(1,"Result latency mismatch: tick=%0d center=%0d",tick,result_tag);
            checks=checks+1;
        end
        if(valid_pipe[4] && tick-display_tag != 1061)
            $fatal(1,"Extra display register latency mismatch");
    end
    initial begin
        // Feed labels representing the actual pixel-clock index.
        // The first pixel is sampled at tick=1; tick=0 is blank.
        for(drive_tick=1;drive_tick<=1056*9;drive_tick=drive_tick+1) begin
            @(negedge clk);
            x=(drive_tick-1)%1056;
            y=(drive_tick-1)/1056;
            clken=(x<800);
            pixel_tag=drive_tick;
        end
        repeat(5) @(negedge clk);
        if(checks<4000) $fatal(1,"Insufficient checks: %0d",checks);
        $display("PASS: %0d interior-pixel checks; 2 taps x 800 plus current input; 1056 clocks/line; center-to-3-stage-result=1060 clocks; plus display register=1061 clocks",checks);
        $finish;
    end
endmodule


