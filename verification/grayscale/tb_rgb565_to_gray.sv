`timescale 1ns/1ps
module tb_rgb565_to_gray;
    reg [15:0] rgb565;
    wire [7:0] gray8;
    integer pixel, r5, g6, b5, r, g, b, expected, ideal, delta;
    integer max_error;
    rgb565_to_gray dut (.rgb565(rgb565), .gray8(gray8));
    initial begin
        max_error = 0;
        for (pixel = 0; pixel < 65536; pixel = pixel + 1) begin
            rgb565 = pixel;
            #1;
            r5 = (pixel / 2048) % 32;
            g6 = (pixel / 32) % 64;
            b5 = pixel % 32;
            r = r5 * 8 + r5 / 4;
            g = g6 * 4 + g6 / 16;
            b = b5 * 8 + b5 / 4;
            expected = (77*r + 150*g + 29*b + 128) / 256;
            if ((^gray8 === 1'bx) || gray8 !== expected[7:0]) begin
                $fatal(1, "Mismatch: RGB565=%h actual=%d expected=%d", rgb565, gray8, expected);
            end
            ideal = $rtoi(0.299*r + 0.587*g + 0.114*b + 0.5);
            delta = gray8 - ideal;
            if (delta < 0) delta = -delta;
            if (delta > max_error) max_error = delta;
            if (delta > 1) $fatal(1, "Luma approximation error exceeds one level");
            if ((pixel == 0 && gray8 != 0) ||
                (pixel == 65535 && gray8 != 255) ||
                (pixel == 63488 && gray8 != 77) ||
                (pixel == 2016 && gray8 != 149) ||
                (pixel == 31 && gray8 != 29))
                $fatal(1, "Black/white/primary-color check failed");
        end
        $display("PASS: all 65536 RGB565 inputs; no unknown outputs; black=0 white=255 R=77 G=149 B=29; max BT.601 error=%0d", max_error);
        $finish;
    end
endmodule
