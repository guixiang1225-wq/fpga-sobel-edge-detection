`timescale 1ns/1ps
module tb_startup;
 localparam W=800,H=480,HT=1056,VT=525,F=HT*VT,D=HT+4,P=W*H;
 reg clk=0,wrclk=0,rst_n=0;
 always #5 clk=~clk;
 always #1.32 wrclk=~wrclk;
 reg [15:0] inputs[0:4*P-1],gold[0:4*P-1];
 wire [15:0] q,rgb,old_rgb;
 wire empty,full,req,old_req,hs,vs,de,fault,old_fault;
 wire [9:0] used,wused;
 reg wrreq=0;
 reg [15:0] wrdata=0;
 integer tick=0,write_index=0,remaining=0,read_index=0;
 integer t,ot,oh,ov,ox,oy,source_h,source_v,checks=0,white_pixels=0;
 integer output_frame,read_frame_pixels=0;
 reg expected_de,expected_hs,expected_vs;
 reg [15:0] expected_rgb;
 Sdram_RD_FIFO fifo(
   .aclr(!rst_n),.data(wrdata),.rdclk(clk),.rdreq(req),
   .wrclk(wrclk),.wrreq(wrreq),.q(q),.rdempty(empty),
   .rdusedw(used),.wrfull(full),.wrusedw(wused)
 );
 sobel_video_pipeline dut(
   .clk(clk),.rst_n(rst_n),.key_up_n(1'b1),.key_down_n(1'b1),
   .rgb565(q),.fifo_empty(empty),.fifo_used(used),.data_req(req),
   .tft_rgb(rgb),.tft_hs(hs),.tft_vs(vs),.tft_de(de),
   .underflow_sticky(fault)
 );
 // Old code at threshold zero must still stay black after the first empty.
 sobel_video_pipeline_before #(.THRESHOLD(11'd0)) old_dut(
   .clk(clk),.rst_n(rst_n),.key_up_n(1'b1),.key_down_n(1'b1),
   .rgb565(q),.fifo_empty(empty),.data_req(old_req),
   .tft_rgb(old_rgb),.tft_hs(),.tft_vs(),.tft_de(),
   .underflow_sticky(old_fault)
 );
 // Delayed camera/controller availability. Refill by 256-word bursts at
 // the SDRAM clock rate using the real asynchronous show-ahead FIFO.
 // Delay extends across multiple complete TFT scans and ends mid-frame.
 always @(negedge wrclk) begin
   wrreq=0;
   if(!rst_n) begin write_index=0;remaining=0; end
   else if(tick>=2*F+60000) begin
     if(remaining==0 && wused<256) remaining=256;
     if(remaining>0) begin
       if(full) $fatal(1,"Unexpected FIFO overflow");
       wrdata=inputs[3*P+write_index];wrreq=1;
       write_index=(write_index+1)%P;
       remaining=remaining-1;
     end
   end
 end
 always @(posedge clk) begin
  if(!rst_n) begin tick=0;read_index=0; end
  else begin
   t=tick;source_h=t%HT;source_v=(t/HT)%VT;
   if(t<3*F && req) $fatal(1,"Read started before next frame boundary");
   if(t>=3*F && t<5*F) begin
     if(req !== (source_h>=216 && source_h<1016 && source_v>=35 && source_v<515))
       $fatal(1,"Running read request/raster mismatch");
   end
   if(req) begin
     if(empty) $fatal(1,"New pipeline read empty FIFO");
     if(q !== inputs[3*P+read_index])
       $fatal(1,"FIFO pixel mismatch at read_index=%0d",read_index);
     if(read_index==0 && (source_h!=216 || source_v!=35))
       $fatal(1,"First queued pixel is not at x=0,y=0");
     read_index=(read_index+1)%P;
     read_frame_pixels=read_frame_pixels+1;
   end
   #1;
   if(fault !== 0) $fatal(1,"Expected startup empty incorrectly became sticky fault");
   if(t>40000 && old_fault !== 1) $fatal(1,"Old permanent-black fault not reproduced");
   if(old_rgb !== 0) $fatal(1,"Old code unexpectedly recovered");
   expected_de=0;expected_hs=0;expected_vs=0;expected_rgb=0;
   if(t>=D) begin
     ot=t-D;oh=ot%HT;ov=(ot/HT)%VT;
     expected_hs=oh>=128;expected_vs=ov>=2;
     expected_de=(oh>=216 && oh<1016 && ov>=35 && ov<515);
     output_frame=ot/F;
     if(expected_de && output_frame>=3 && output_frame<5) begin
       ox=oh-216;oy=ov-35;
       expected_rgb=gold[3*P+oy*W+ox];
       checks=checks+1;
       if(expected_rgb!=0) white_pixels=white_pixels+1;
     end
   end
   if({hs,vs,de} !== {expected_hs,expected_vs,expected_de})
      $fatal(1,"TFT sync changed during startup");
   if(rgb !== expected_rgb)
      $fatal(1,"Startup recovery pixel mismatch tick=%0d x=%0d y=%0d got=%h expected=%h",t,ox,oy,rgb,expected_rgb);
   #1;tick=tick+1;
  end
 end
 initial begin
   $readmemh("../sobel/input_rgb.hex",inputs);
   $readmemh("../sobel/gold_binary.hex",gold);
   repeat(4) @(negedge clk);rst_n=1;
   wait(tick>=5*F+D+4);
   @(negedge clk);
   if(checks!=2*P || read_frame_pixels!=2*P || white_pixels<1000)
      $fatal(1,"Coverage failure: output=%0d reads=%0d white=%0d",checks,read_frame_pixels,white_pixels);
   $display("PASS: old threshold=0 remains black after startup empty; corrected pipeline waits through multiple scans, starts at frame origin, and matches %0d pixels over 2 frames with real asynchronous FIFO; white pixels=%0d; no underrun; D=1060",checks,white_pixels);
   $finish;
 end
 initial begin #30000000;$fatal(1,"Startup test timeout");end
endmodule
