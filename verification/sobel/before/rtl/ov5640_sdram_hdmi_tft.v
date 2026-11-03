module ov5640_sdram_hdmi_tft(
	input 			clk,
	input 			rst_n,
	
	//sdram control
	output			sdram_clk,
	output			sdram_cke,
	output			sdram_cs_n,
	output			sdram_we_n,
	output			sdram_cas_n,
	output			sdram_ras_n,
	output  [1:0]	sdram_dqm,
	output  [1:0]	sdram_ba,
	output  [12:0]	sdram_addr,
	inout   [15:0]	sdram_dq,
	
	//cmos interface
	output			camera_sclk,
	inout				camera_sdat,
	input				camera_vsync,
	input				camera_href,
	input				camera_pclk,
	output			camera_xclk,
	input 	[7:0]	camera_data,
	output			camera_rst_n,
	output			camera_pwdn,
	
	//tft output
	output  [15:0]  tft_rgb,  //TFT数据输出
	output          tft_hs,   //TFT行同步信号
	output          tft_vs,   //TFT场同步信号
	output          tft_clk,  //TFT像素时钟
	output          tft_de,   //TFT数据使能
	output          tft_pwm  //TFT背光控制
);
	wire clk_sdr_ctrl;
	wire clk_50m;
	wire clk_24m;
	assign camera_xclk = clk_24m;
	pll pll_inst (
		.inclk0(clk),
		.c0(clk_sdr_ctrl),
		.c1(sdram_clk),
		.c2(clk_50m),
		.c3(clk_24m)
	);
	
	wire clk_tft; // 33 MHz TFT pixel clock
	pll_hdmi pll_hdmi_inst(
		.inclk0(clk),
		.c0(clk_tft),
		.c1()
	);
	
	localparam RGB = 0;
	
	parameter IMAGE_WIDTH  = 800; //图片宽度
	parameter IMAGE_HEIGHT = 480; //图片高度(≤720)
	parameter IMAGE_FLIP   = 0;   //0：不翻转，1：上下翻转
	parameter IMAGE_MIRROR = 0;   //0：不镜像，1：左右镜像

	//摄像头初始化配置
	wire Init_Done;
	camera_init
	#(
		.IMAGE_TYPE(RGB),
		.IMAGE_WIDTH(IMAGE_WIDTH),
		.IMAGE_HEIGHT(IMAGE_HEIGHT),
		.IMAGE_FLIP(IMAGE_FLIP),
		.IMAGE_MIRROR(IMAGE_MIRROR)
	)
	camera_init(
		.Clk(clk_50m),
		.Rst_n(rst_n),
		.Init_Done(Init_Done),
		.camera_rst_n(camera_rst_n),
		.camera_pwdn(camera_pwdn),
		.i2c_sclk(camera_sclk),
		.i2c_sdat(camera_sdat)
	);
	
	//-----------------------------------------------
	//摄像头图像输出
	wire fifo_aclr;
	wire fifo_wrreq;
	wire [15:0] fifo_wrdata;
	DVP_Capture DVP_Capture(
		.Rst_n(Init_Done),
		.PCLK(camera_pclk),
		.Vsync(camera_vsync),
		.Href(camera_href),
		.Data(camera_data),
		.ImageState(fifo_aclr),
		.DataValid(fifo_wrreq),
		.DataPixel(fifo_wrdata),
		.Xaddr(),
		.Yaddr()
	);
	
	wire [15:0] RGB_DATA;
	wire DataReq;
	Sdram_Control_4Port Sdram_Control_4Port(
		//	HOST Side
		.CTRL_CLK(clk_sdr_ctrl),	//输入参考时钟，默认100M，如果为其他频率，请修改sdram_pll核设置
		.RESET_N(rst_n),	//复位输入，低电平复位

		//	FIFO Write Side 1
		.WR1_DATA(fifo_wrdata),			//写入端口1的数据输入端，16bit
		.WR1(fifo_wrreq),					//写入端口1的写使能端，高电平写入
		.WR1_ADDR(0),			//写入端口1的写起始地址
		.WR1_MAX_ADDR(IMAGE_WIDTH * IMAGE_HEIGHT),		//写入端口1的写入最大地址
		.WR1_LENGTH(256),			//一次性写入数据长度
		.WR1_LOAD(fifo_aclr),			//写入端口1清零请求，高电平清零写入地址和fifo
		.WR1_CLK(camera_pclk),				//写入端口1 fifo写入时钟
		.WR1_FULL(),			//写入端口1 fifo写满信号
		.WR1_USE(),				//写入端口1 fifo已经写入的数据长度

		//	FIFO Read Side 1
		.RD1_DATA(RGB_DATA),			//读出端口1的数据输出端，16bit
		.RD1(DataReq),					//读出端口1的读使能端，高电平读出
		.RD1_ADDR(0),			//读出端口1的读起始地址
		.RD1_MAX_ADDR(IMAGE_WIDTH * IMAGE_HEIGHT),		//读出端口1的读出最大地址
		.RD1_LENGTH(256),			//一次性读出数据长度
		.RD1_LOAD(!rst_n),			//读出端口1 清零请求，高电平清零读出地址和fifo
		.RD1_CLK(clk_tft),			//读出端口1 fifo读取时钟
		.RD1_EMPTY(),			//读出端口1 fifo读空信号
		.RD1_USE(),				//读出端口1 fifo已经还可以读取的数据长度

		//	SDRAM Side
		.SA(sdram_addr),		//SDRAM 地址线，
		.BA(sdram_ba),		//SDRAM bank地址线
		.CS_N(sdram_cs_n),		//SDRAM 片选信号
		.CKE(sdram_cke),		//SDRAM 时钟使能
		.RAS_N(sdram_ras_n),	//SDRAM 行选中信号
		.CAS_N(sdram_cas_n),	//SDRAM 列选中信号
		.WE_N(sdram_we_n),		//SDRAM 写请求信号
		.DQ(sdram_dq),		//SDRAM 双向数据总线
		.DQM(sdram_dqm)		//SDRAM 数据总线高低字节屏蔽信号
	);
	
	wire        video_hs;
	wire        video_vs;
	wire        video_de;
	wire        video_clk;
	wire [7:0]  video_r;
	wire [7:0]  video_g;
	wire [7:0]  video_b;
    wire [7:0] gray8;
    rgb565_to_gray u_rgb565_to_gray (
        .rgb565(RGB_DATA),
        .gray8(gray8)
    );
	disp_driver disp_driver(
		.ClkDisp		(clk_tft				),
		.Rst_n			(rst_n					),
		.Data			({gray8,gray8,gray8}),
		.DataReq		(DataReq				),
		.H_Addr			(),
		.V_Addr			(),
		.Disp_HS		(video_hs				),
		.Disp_VS		(video_vs				),
		.Disp_Red		(video_r				),
		.Disp_Green		(video_g				),
		.Disp_Blue		(video_b				),
		.Disp_DE		(video_de				),
		.Disp_PCLK		(video_clk 				)
	);
	
	//tft display
	assign tft_rgb = {video_r[7:3], video_g[7:2], video_b[7:3]};  //TFT数据输出
	assign tft_hs = video_hs;
	assign tft_vs = video_vs;
	assign tft_clk = video_clk;
	assign tft_de = video_de;
	assign tft_pwm = rst_n;
	
endmodule
