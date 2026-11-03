`timescale 1ns/1ps
module tb_threshold_keys;
 reg clk=0,rst_n=0,prep=0,up_n=1,down_n=1;
 always #5 clk=~clk;
 wire [10:0] requested,active;
 wire [7:0] edge8;
 wire edge_valid;
 integer up_count=0,down_count=0,n;
 sobel_threshold_keys #(.DEBOUNCE_CYCLES(8)) dut (
  .clk(clk),.rst_n(rst_n),.frame_prepare(prep),.key_up_n(up_n),.key_down_n(down_n),
  .threshold_requested(requested),.threshold_active(active)
 );
 // A stable synthetic 3x3 window produces Gx=0, Gy=128.
 sobel_filter core (
  .clk(clk),.rst_n(rst_n),.frame_prepare(prep),.in_valid(1'b1),
  .in_x(10'd10),.in_y(9'd10),.gray_in(8'd32),.row1(8'd0),.row2(8'd0),
  .threshold(active),.edge8(edge8),.edge_valid(edge_valid),.edge_x(),.edge_y()
 );
 always @(posedge clk) if(rst_n) begin
  if(dut.up_pulse) up_count=up_count+1;
  if(dut.down_pulse) down_count=down_count+1;
  #1;
  if(requested>2040 || active>2040 || (^requested===1'bx) || (^active===1'bx))
   $fatal(1,"Threshold invalid or overflow");
 end
 task ticks(input integer count); begin repeat(count) @(negedge clk);end endtask
 task check(input integer want_req,input integer want_active);
  begin
   if(requested!==want_req[10:0] || active!==want_active[10:0])
    $fatal(1,"Threshold mismatch requested=%0d/%0d active=%0d/%0d",requested,want_req,active,want_active);
  end
 endtask
 task publish(input integer want);
  begin
   prep=1;ticks(1);prep=0;ticks(10);check(want,want);
   if(!edge_valid || edge8 !== ((128>=want)?8'hff:8'h00))
    $fatal(1,"Dynamic Sobel threshold did not affect output");
  end
 endtask
 task release_keys; begin up_n=1;down_n=1;ticks(24);end endtask
 initial begin
  ticks(4);rst_n=1;ticks(24);check(128,128);
  // Several short glitches never count as a press.
  repeat(6) begin up_n=0;ticks(2);up_n=1;ticks(2);end
  ticks(24);check(128,128);
  if(up_count!=0)$fatal(1,"Bounce generated a press");
  up_n=0;ticks(24);check(136,128);
  ticks(200);check(136,128);
  if(up_count!=1)$fatal(1,"Held button repeated");
  // Release bounce cannot retrigger without a debounced release.
  repeat(6) begin up_n=1;ticks(2);up_n=0;ticks(2);end
  release_keys;check(136,128);
  if(up_count!=1)$fatal(1,"Release bounce generated a press");
  publish(136);
  down_n=0;ticks(24);check(128,136);release_keys;publish(128);
  up_n=0;down_n=0;ticks(24);check(128,128);
  release_keys;publish(128);
  for(n=0;n<300;n=n+1) begin up_n=0;ticks(20);release_keys;end
  check(2040,128);publish(2040);
  for(n=0;n<300;n=n+1) begin down_n=0;ticks(20);release_keys;end
  check(0,2040);publish(0);
  up_n=0;ticks(20);release_keys;
  up_n=0;ticks(20);release_keys;
  check(16,0);publish(16);
  rst_n=0;ticks(4);rst_n=1;ticks(24);check(128,128);
  $display("PASS: bounce/short-glitch rejection; long-hold single pulse; release rearm; +/-8; simultaneous cancel; saturation 0..2040; frame-latched threshold; live Sobel equality/threshold output; reset; up_pulses=%0d down_pulses=%0d",up_count,down_count);
  $finish;
 end
 initial begin #10000000;$fatal(1,"Timeout");end
endmodule
