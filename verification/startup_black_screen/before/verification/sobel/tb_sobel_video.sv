`timescale 1ns/1ps
module tb_sobel_video;
 localparam W=800,H=480,HT=1056,VT=525,F=HT*VT,D=HT+4,N=4*W*H;
 reg clk=0,rst_n=0;
 always #5 clk=~clk;
 reg [15:0] input_rgb[0:N-1],gold_binary[0:N-1],gold_magnitude[0:N-1];
 reg [7:0] input_gray[0:N-1];
 integer source_tick=0,phase=0;
 integer hpos,vpos,px,py,frame_id,idx;
 reg active;
 reg [15:0] rgb;
 reg fifo_empty=0;
 wire req_b,req_m,hs_b,vs_b,de_b,hs_m,vs_m,de_m,err_b,err_m;
 wire [15:0] rgb_b,rgb_m;
 integer t,ot,oh,ov,ox,oy,oframe,oi;
 integer checks=0,window_checks=0,rows_checks=0,fault_checks=0;
 integer counts[0:3],valid_counts[0:3];
 integer n;
 reg ed,eh,ev;
 reg [15:0] eb,em;
 reg [71:0] expected_window;
 reg expected_fault=0;
 sobel_video_pipeline #(.BINARY_MODE(1)) dut (
  .clk(clk),.rst_n(rst_n),.rgb565(rgb),.fifo_empty(fifo_empty),
  .key_up_n(1'b1),.key_down_n(1'b1),
  .data_req(req_b),.tft_rgb(rgb_b),.tft_hs(hs_b),.tft_vs(vs_b),.tft_de(de_b),
  .underflow_sticky(err_b)
 );
 sobel_video_pipeline #(.BINARY_MODE(0)) dut_mag (
  .clk(clk),.rst_n(rst_n),.rgb565(rgb),.fifo_empty(fifo_empty),
  .key_up_n(1'b1),.key_down_n(1'b1),
  .data_req(req_m),.tft_rgb(rgb_m),.tft_hs(hs_m),.tft_vs(vs_m),.tft_de(de_m),
  .underflow_sticky(err_m)
 );
 always @* begin
  hpos=source_tick%HT; vpos=(source_tick/HT)%VT;
  frame_id=source_tick/F;
  active=(hpos>=216 && hpos<1016 && vpos>=35 && vpos<515);
  px=hpos-216;py=vpos-35;
  idx=frame_id*W*H+py*W+px;
  rgb=16'hxxxx;
  if(active && frame_id<4) rgb=input_rgb[(phase==2 ? 3*W*H+py*W+px : idx)];
  fifo_empty=(phase==1 && active && py==20 && px==100);
 end
 always @(posedge clk) begin
  if(!rst_n) begin source_tick=0;expected_fault=0; end
  else begin
   t=source_tick;
   if(req_b !== active || req_m !== active) $fatal(1,"Read request/raster mismatch t=%0d",t);
   if(active && phase==0 && py>=2) begin
    if(dut.row1 !== input_gray[idx-W] || dut.row2 !== input_gray[idx-2*W])
      $fatal(1,"Row taps mismatch x=%0d y=%0d frame=%0d",px,py,frame_id);
    rows_checks=rows_checks+1;
   end
   if(active && fifo_empty) expected_fault=1;
   if(active && phase==0 && px>=2 && py>=2)
    expected_window={input_gray[idx-2*W-2],input_gray[idx-2*W-1],input_gray[idx-2*W],
                     input_gray[idx-W-2],input_gray[idx-W-1],input_gray[idx-W],
                     input_gray[idx-2],input_gray[idx-1],input_gray[idx]};
   #1;
   if(err_b !== expected_fault || err_m !== expected_fault) $fatal(1,"Fault latch mismatch");
   if(active && phase==0 && px>=2 && py>=2) begin
    if({dut.u_sobel.p11,dut.u_sobel.p12,dut.u_sobel.p13,
        dut.u_sobel.p21,dut.u_sobel.p22,dut.u_sobel.p23,
        dut.u_sobel.p31,dut.u_sobel.p32,dut.u_sobel.p33} !== expected_window)
       $fatal(1,"3x3 matrix mismatch x=%0d y=%0d frame=%0d",px,py,frame_id);
    window_checks=window_checks+1;
   end
   ed=0;eh=0;ev=0;eb=0;em=0;ox=0;oy=0;oframe=0;
   if(t>=D) begin
    ot=t-D;oh=ot%HT;ov=(ot/HT)%VT;oframe=ot/F;
    eh=(oh>=128);ev=(ov>=2);
    ed=(oh>=216 && oh<1016 && ov>=35 && ov<515);
    if(ed) begin
     ox=oh-216;oy=ov-35;oi=oframe*W*H+oy*W+ox;
     if(!expected_fault) begin eb=gold_binary[(phase==2 ? 3*W*H+oy*W+ox : oi)];em=gold_magnitude[(phase==2 ? 3*W*H+oy*W+ox : oi)];end
    end
   end
   if({hs_b,vs_b,de_b} !== {eh,ev,ed} ||
      {hs_m,vs_m,de_m} !== {eh,ev,ed})
       $fatal(1,"TFT control phase mismatch t=%0d",t);
   if(rgb_b !== eb || rgb_m !== em)
       $fatal(1,"Pixel mismatch t=%0d frame=%0d x=%0d y=%0d bin=%h/%h mag=%h/%h",
                  t,oframe,ox,oy,rgb_b,eb,rgb_m,em);
   if(ed && phase==0) begin
    counts[oframe]=counts[oframe]+1; checks=checks+1;
    if(ox>0 && ox<W-1 && oy>0 && oy<H-1) begin
     if(dut.ev !== 1'b1 || dut.ex !== ox[9:0] || dut.ey !== oy[8:0])
       $fatal(1,"Center valid/coordinates mismatch");
     valid_counts[oframe]=valid_counts[oframe]+1;
    end
   end
   if(expected_fault) fault_checks=fault_checks+1;
   #1;source_tick=source_tick+1;
  end
 end
 initial begin
  $readmemh("input_rgb.hex",input_rgb);$readmemh("input_gray.hex",input_gray);
  $readmemh("gold_binary.hex",gold_binary);$readmemh("gold_magnitude.hex",gold_magnitude);
  for(n=0;n<4;n=n+1) begin counts[n]=0;valid_counts[n]=0;end
  repeat(4) @(negedge clk);rst_n=1;
  wait(source_tick>=4*F+D+4);
  @(negedge clk);rst_n=0;
  for(n=0;n<4;n=n+1) begin
   if(counts[n]!=W*H || valid_counts[n]!=(W-2)*(H-2))
      $fatal(1,"Frame pixel count mismatch frame=%0d total=%0d interior=%0d",n,counts[n],valid_counts[n]);
   $display("FRAME %0d PASS: pixels=%0d interior=%0d",n,counts[n],valid_counts[n]);
  end
  phase=1;repeat(4) @(negedge clk);rst_n=1;
  wait(source_tick>=F/2);
  @(negedge clk);rst_n=0;
  if(fault_checks<1000) $fatal(1,"Fault path not exercised");
  phase=2;repeat(4) @(negedge clk);rst_n=1;
  wait(source_tick>=80*HT);
  @(negedge clk);rst_n=0;
  $display("PASS: four full 800x480 frames; binary and magnitude pixel-exact; %0d pixels; %0d matrices; %0d row pairs; %0d fault clocks; D=1060; reset recovery verified",
           checks,window_checks,rows_checks,fault_checks);
  $finish;
 end
 initial begin #30000000; $fatal(1,"Simulation timeout");end
endmodule
