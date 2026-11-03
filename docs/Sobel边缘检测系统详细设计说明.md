> 最新更新（2026-11-02）：旧按键版上板全黑已定位为启动FIFO空误触发永久屏蔽。现已修复、仿真与编译通过，新SOF尚未下载。当前接口及结果见[Sobel黑屏问题检查与修复](Sobel黑屏问题检查与修复.md)，下文原版本SOF与下载记录为历史。

# 摄像头—SDRAM—Sobel—TFT 系统详细设计说明

版本：1.0；日期：2026-11-02；目标器件：Cyclone IV E EP4CE10F17C8；工具：Quartus II 13.0、ModelSim SE-64 2020.4。

工程位置：D:\gx2026\project\camera_sdram_tft_sobel。

> **实施更新（2026-11-02）：** 已完成读出侧Sobel、四帧逐像素验证与Quartus全编译。下文保留设计基线推导；实际接口、欠载锁存策略和最终验证见[《Sobel项目实施与验证结果》](Sobel项目实施与验证结果.md)。本次未连接板卡，未确认实屏。

> 以下为实施前设计基线：本文是待实施的 Sobel 设计方案。当前生产 RTL 仍为已经上板显示过的灰度工程，尚未集成完整 Sobel。本文列出的新增模块接口是设计约定，不表示这些模块已经存在。既有 1060 周期结论来自 IP 模型和像素标签仿真，不能代替完整算法、边界、TFT 接口及布局布线验证。

## 目录

1. 目标、现状与参数
2. 总体结构和模块清单
3. 现有系统各模块接口
4. 新增和改造模块接口
5. Sobel 运算、位宽与流水
6. 中心像素到运算结果的延迟推导
7. Sobel 与 TFT 的对齐方法
8. 消隐、边界、帧切换与异常
9. 实施顺序和验证标准
10. 资源、限制与证据
11. 既有叶子模块接口声明附录

## 1. 目标、现状与参数

### 1.1 目标与范围

摄像头采集 RGB565，经 SDRAM 缓冲后，在读出端完成 RGB565 转灰度、3×3 Sobel，再通过 TFT 显示。保持 800×480 有效区和原有引脚。四周一像素置黑，内部 798×478 输出有效边缘结果。

按用户要求，将原计划的 matrix_3x3 和 sobel_core 合并为一个 sobel_filter：内部九个 8 位寄存器组成窗口，后接算术流水，不再设置独立矩阵模块。

原始资料工程、彩色副本、灰度副本不修改。后续实现仅操作本 Sobel 副本，并在副本修改说明中记录变更。本次只生成文档，不修改生产 RTL、IP、QSF、QPF 或 SOF。

### 1.2 当前确认的配置

| 项目 | 当前值/约定 |
|---|---|
| 摄像头 | OV5640，8 位 DVP 总线，每像素两字节，高字节先到 |
| SDRAM 像素格式 | RGB565，R=[15:11]、G=[10:5]、B=[4:0] |
| SDRAM 控制器 | 实际只有 WR1/RD1；保留历史模块名 Sdram_Control_4Port |
| 灰度格式 | 无符号 8 位，范围 0～255 |
| 显示逻辑格式 | 当前 disp_driver 内部 RGB888，TFT 引脚 RGB565 |
| 图像有效大小 | 800×480 |
| TFT 像素时钟 | 33 MHz，周期约 30.303 ns |
| 水平周期 | 1056 时钟：128 同步＋88 后肩＋800 有效＋40 前肩 |
| 垂直周期 | 525 行；2 同步、25 后肩、8 上边界、480 有效、8 下边界、2 前肩 |
| 总帧周期 | 1056×525=554400 个像素时钟，约 16.8 ms，约 59.52 Hz |
| 主方案行缓存 | ALTSHIFT_TAPS：宽度 8、抽头数 2、抽头间距 800 |
| 主方案算术流水 | Gx/Gy → 幅值 → 阈值/饱和，共三级 |
| 目标相对延迟 | 中心像素被输入采样到结果寄存：1060 个时钟间隔 |

注意：表中的垂直“上边界/下边界”属于原扫描参数，不是 Sobel 新增的一像素算法边框。

### 1.3 时钟域

| 时钟 | 现有作用 |
|---|---|
| clk，50 MHz | 板载参考时钟 |
| camera_pclk | 摄像头输出时钟，采样 DVP，驱动写 FIFO 的写侧 |
| clk_sdr_ctrl，125 MHz | SDRAM 控制器和 FIFO 的 SDRAM 侧 |
| sdram_clk，125 MHz | SDRAM 外部时钟，现有 PLL 相移约 -2000 ps |
| clk_50m，50 MHz | 摄像头寄存器初始化 |
| camera_xclk，约 24.038 MHz | 摄像头外部参考时钟 |
| clk_tft，33 MHz | 读 FIFO 的读侧、灰度/Sobel/TFT 显示 |

新增处理全部放在 clk_tft 域，不新增跨时钟域。双时钟 FIFO 继续承担原有跨域功能。SDRAM 参数文件的活动区标注“100 MHz”，与实际 125 MHz 配置不一致，是继承的待核查项，不在本文中擅自修改。

## 2. 总体结构和模块清单

### 2.1 数据路径

```text
OV5640 --8位DVP--> DVP_Capture --RGB565--> 写FIFO
                                           |
                                      SDRAM控制器
                                           |
                                         SDRAM
                                           |
                                        读FIFO
                                           |
                                      RGB_DATA[15:0]
                                           |
                                     rgb565_to_gray
                                           |
                                         gray8
                              +------------+------------+
                              |                         |
                       gray_line_buffer                 |
                       两个历史行抽头                   |
                              |                         |
                              +----> sobel_filter <-----+
                                   九像素寄存窗口
                                   三级算术流水
                                           |
                                       edge8/valid
                                           |
                                  video_output_align
                                  边界填黑/同步对齐
                                           |
                                    TFT RGB565 + HS/VS/DE
```

### 2.2 控制路径

```text
tft_timing_gen（从现有 disp_driver 提取扫描功能）
   ├─ 原始 src_de/DataReq → SDRAM读FIFO → 灰度与Sobel输入
   ├─ src_x/src_y、帧准备脉冲 → 行缓存及窗口有效管理
   └─ 同像素基准的 src_hs/src_vs/src_de → 输出对齐 → TFT同步信号
```

最终 TFT 的 DE 不反馈给 SDRAM。取数依据原始扫描节奏，输出依据处理后中心像素节奏，两者之间存在固定相位差。

### 2.3 全部功能模块及实施状态

| 模块 | 状态/处理方式 | 功能 |
|---|---|---|
| ov5640_sdram_hdmi_tft | 修改内部连接，保留顶层实体名 | 系统集成及板级端口 |
| pll、pll_hdmi | 保留 | 各域时钟；pll_hdmi 仅使用 c0 的 33 MHz |
| camera_init | 保留 | 摄像头复位、寄存器配置 |
| ov5640_init_table_rgb | 保留 | RGB565/分辨率/方向寄存器表 |
| i2c_control、i2c_bit_shift | 保留 | 寄存器事务及 I2C 位级传输 |
| DVP_Capture | 保留 | 两个字节拼接 RGB565，产生写入有效 |
| Sdram_Control_4Port | 保留现有 WR1/RD1 | 双 FIFO、SDRAM 突发与刷新调度 |
| Sdram_WR_FIFO、Sdram_RD_FIFO | 保留 | 双时钟 FIFO |
| control_interface、command、sdr_data_path | 保留 | SDRAM 命令、时序、数据通路 |
| rgb565_to_gray | 复用 | 组合 RGB565 转 8 位灰度 |
| disp_driver | 提取扫描功能；原像素输出门控不再直接使用 | 现有扫描/RGB 输出耦合模块 |
| tft_timing_gen | 新增/由 disp_driver 改造 | 原始扫描及精确定义的取数元数据 |
| gray_line_buffer | 新增 | 封装两抽头 Shift Register IP |
| gray_line_shift（ALTSHIFT_TAPS） | 新增 IP | 两行历史存储 |
| sobel_filter | 新增 | 合并窗口与 Sobel 算术 |
| video_output_align | 新增 | 同步延迟、边框、RGB565 输出 |

ov5640_init_table_jpeg 是源码中的备用分支，RGB 模式下不参与当前硬件。dvi_encoder.v 已无模块定义。rtl/Sdram_Control_2Port 下的历史独立实现不在当前 QSF 活动源列表，不应重复加入。ALTSHIFT_TAPS、dcfifo、altpll 等厂商内部层级由 IP 库提供，不要求逐个重写。

## 3. 现有系统各模块接口

本章 I/O 方向均相对该模块本身。宏 ASIZE=24、DSIZE=16；叶子模块完整声明见附录。

### 3.1 系统顶层 ov5640_sdram_hdmi_tft

| 端口 | 方向/位宽 | 功能 |
|---|---|---|
| clk、rst_n | 输入，各1 | 50 MHz 参考时钟、低有效复位 |
| camera_pclk、camera_vsync、camera_href | 输入，各1 | DVP 像素时钟、场同步、行有效 |
| camera_data | 输入8 | 摄像头像素字节 |
| camera_xclk、camera_rst_n、camera_pwdn | 输出，各1 | 摄像头参考时钟、复位、掉电控制 |
| camera_sclk、camera_sdat | 输出1、双向1 | 摄像头配置总线 |
| sdram_clk、sdram_cke、sdram_cs_n、sdram_we_n、sdram_cas_n、sdram_ras_n | 输出，各1 | SDRAM 时钟及控制 |
| sdram_addr、sdram_ba、sdram_dqm | 输出13、2、2 | SDRAM 地址、Bank、字节屏蔽 |
| sdram_dq | 双向16 | SDRAM 数据 |
| tft_rgb | 输出16 | {R5,G6,B5}，边缘灰度复制后量化 |
| tft_clk、tft_hs、tft_vs、tft_de、tft_pwm | 输出，各1 | 像素时钟、同步、数据有效、背光 |

参数 IMAGE_WIDTH=800、IMAGE_HEIGHT=480，IMAGE_FLIP/IMAGE_MIRROR 沿用当前值0。新增 Sobel 不改变摄像头方向。

### 3.2 pll / pll_hdmi

pll：inclk0 为输入；c0～c4 为输出。当前 c0=125 MHz、c1=125 MHz 带相移、c2=50 MHz、c3约24.038 MHz，c4=31.25 MHz 未连接。

pll_hdmi：inclk0 为输入，c0=33 MHz TFT 时钟，c1=165 MHz 未连接。保留历史命名不表示仍有 HDMI 显示逻辑。所有端口宽度均为1。

### 3.3 camera_init 与寄存器表

| 模块 | 接口 | 功能及约定 |
|---|---|---|
| camera_init | 输入 Clk、Rst_n；输出 Init_Done、camera_rst_n、camera_pwdn、i2c_sclk；双向 i2c_sdat | Clk=50 MHz；配置完成置 Init_Done；参数为 IMAGE_TYPE/WIDTH/HEIGHT/FLIP/MIRROR |
| ov5640_init_table_rgb | 输入 clk、addr[7:0]；输出 q[23:0] | q 包含16位寄存器地址和8位数据；同步查表；DATA_WIDTH/ADDR_WIDTH 可参数化 |
| ov5640_init_table_jpeg | 接口同 RGB 表 | 备用 JPEG 分支，主方案不启用 |

### 3.4 i2c_control / i2c_bit_shift

| 模块 | 输入 | 输出/双向 | 功能 |
|---|---|---|---|
| i2c_control | Clk、Rst_n、wrreg_req、rdreg_req、addr[15:0]、addr_mode、wrdata[7:0]、device_id[7:0] | rddata[7:0]、RW_Done、ack、i2c_sclk；双向 i2c_sdat | 将一次读写寄存器请求分解成总线命令；addr_mode 控制地址格式 |
| i2c_bit_shift | Clk、Rst_n、Cmd[5:0]、Go、Tx_DATA[7:0] | Rx_DATA[7:0]、Trans_Done、ack_o、i2c_sclk；双向 i2c_sdat | 执行起始、停止、字节读写和应答；默认 SYS_CLOCK=50 MHz、SCL_CLOCK=400 kHz |

Cmd 位：WR=000001、STA=000010、RD=000100、STO=001000、ACK=010000、NACK=100000。ack 的极性按既有状态机使用，不把变量名称直接解释成“高一定成功”。

### 3.5 DVP_Capture

| 接口 | 方向/位宽 | 功能 |
|---|---|---|
| PCLK、Rst_n | 输入1 | 摄像头时钟、采集复位；当前 Rst_n 接 Init_Done |
| Vsync、Href、Data | 输入1、1、8 | DVP 场同步、行有效、字节 |
| DataPixel、DataValid | 输出16、1 | 拼接的 RGB565 和像素写使能 |
| ImageState | 输出1 | 初始化采集状态，当前接写 FIFO 清零 |
| Xaddr、Yaddr | 输出12、12 | 采集坐标；当前顶层未使用 |

两个有效字节生成一个像素，不能把 camera_pclk 的每一拍都作为一个完整 RGB565 像素。本文 Sobel 坐标来自 SDRAM 读侧，不使用摄像头域坐标跨域直连。

### 3.6 Sdram_Control_4Port（实际两端口）

| 接口组 | 方向/位宽 | 功能 |
|---|---|---|
| CTRL_CLK、RESET_N | 输入1 | SDRAM 域时钟、低有效复位 |
| WR1_DATA、WR1、WR1_CLK | 输入16、1、1 | 摄像头像素、写有效、写侧时钟 |
| WR1_ADDR、WR1_MAX_ADDR | 输入24、24 | 起始和结束上界地址，当前0和384000 |
| WR1_LENGTH、WR1_LOAD | 输入10、1 | 突发长度256、加载地址及 FIFO 清零 |
| WR1_FULL、WR1_USE | 输出1、16 | 写侧状态；USE 外部16位，内部 FIFO 计数10位 |
| RD1_DATA、RD1_EMPTY、RD1_USE | 输出16、1、16 | 读侧像素、空状态、占用数 |
| RD1、RD1_CLK | 输入1、1 | 像素读取请求、33 MHz 读时钟 |
| RD1_ADDR、RD1_MAX_ADDR | 输入24、24 | 当前0和384000 |
| RD1_LENGTH、RD1_LOAD | 输入10、1 | 当前256、读地址/FIFO 清零 |
| SA、BA、CS_N、DQM | 输出12、2、2、2 | SDRAM 地址、Bank、片选和屏蔽 |
| CKE、RAS_N、CAS_N、WE_N | 输出各1 | SDRAM 控制 |
| DQ | 双向16 | SDRAM 数据 |

注意：控制器 SA 为12位，而板级 sdram_addr 为13位；CS_N 为2位而顶层片选为1位，均为原工程已有连接差异。不要在添加 Sobel 时顺便改变这些连接。当前读 FIFO 为 show-ahead：有效队首数据先呈现在 q，RD1 上升沿读请求消费该像素。

固定延迟推导以 FIFO 持续供给有效像素为前提。若空读，固定扫描的 TFT 无法暂停；必须记录异常并重新建立行帧对齐，不能只停窗口而让扫描继续后仍假设1060不变。

### 3.7 SDRAM 叶子模块

| 模块 | 输入 | 输出/双向 | 功能 |
|---|---|---|---|
| Sdram_WR_FIFO / Sdram_RD_FIFO | aclr、data[15:0]、wrclk、wrreq、rdclk、rdreq | q[15:0]、rdempty、wrfull、rdusedw[9:0]、wrusedw[9:0] | 深度512，双时钟 FIFO；写 FIFO 跨 camera_pclk/CTRL_CLK，读 FIFO 跨 CTRL_CLK/clk_tft |
| control_interface | CLK、RESET_N、CMD[2:0]、ADDR[23:0]、REF_ACK、INIT_ACK、CM_ACK | NOP、READA、WRITEA、REFRESH、PRECHARGE、LOAD_MODE、SADDR[23:0]、REF_REQ、INIT_REQ、CMD_ACK | 命令译码、初始化、刷新请求 |
| command | CLK、RESET_N、SADDR[23:0]，NOP/READA/WRITEA/REFRESH/PRECHARGE/LOAD_MODE/REF_REQ/INIT_REQ/PM_STOP/PM_DONE | REF_ACK、CM_ACK、OE、SA[11:0]、BA[1:0]、CS_N[1:0]、CKE/RAS_N/CAS_N/WE_N | SDRAM 命令引脚与读写时序 |
| sdr_data_path | CLK、RESET_N、DATAIN[15:0]、DM[1:0] | DQOUT[15:0]、DQM[1:0] | 写数据直通及屏蔽寄存 |

### 3.8 rgb565_to_gray

输入 rgb565[15:0]，输出 gray8[7:0]，无时钟、复位、valid 输入，完全组合。有效性由外部 src_de 标识。

```text
R8 = {R5,R5[4:2]}
G8 = {G6,G6[5:4]}
B8 = {B5,B5[4:2]}
Y  = (77×R8 + 150×G8 + 29×B8 + 128) >> 8
```

16位无符号中间和最大65408，不溢出。此模块不新增整周期，但有物理传播延迟，仍要计入采样路径。

### 3.9 现有 disp_driver 与必须改造的原因

输入 ClkDisp、Rst_n、Data[23:0]；输出 DataReq、H_Addr[11:0]、V_Addr[11:0]、Disp_HS、Disp_VS、Disp_DE、Disp_PCLK、Disp_Red/Green/Blue[7:0]。

现有 DataReq=Disp_DE；扫描寄存器产生 Disp_DE，另一个时序块按旧的 Disp_DE 采样并门控 RGB。H_Addr/V_Addr 直接组合自当前计数器及已寄存 DE，不能未经校准便作为 Sobel 输入坐标。

改造目标是分离“原始扫描与读取”和“处理后显示”。禁止将 Sobel 输出直接塞回旧 Data，再仅延迟外部 HS/VS/DE：旧门控会提前把处理尾部像素清零，并可能重复增加一级输出寄存器。

## 4. 新增和改造模块接口

以下是拟实施接口，名称可在实施时统一，但宽度、采样边沿和有效性合同应保持一致。全部新增同步逻辑工作在 clk_tft 上升沿。

### 4.1 tft_timing_gen：原始扫描与像素读取

参数：IMAGE_WIDTH=800、IMAGE_HEIGHT=480、H_TOTAL=1056、V_TOTAL=525；其余同步、肩部、边界沿用现有值。

| 端口 | 方向/位宽 | 约定 |
|---|---|---|
| clk、rst_n | 输入各1 | 33 MHz、低有效复位 |
| src_hs、src_vs | 输出各1 | 与输入像素采样基准一致的原始同步电平 |
| src_de | 输出1 | 高时当前 q/gray8 是本次应消费的像素 |
| src_x、src_y | 输出10、9 | 0～799、0～479；src_de 为高时有效 |
| frame_prepare | 输出1 | 每帧首有效像素之前，在消隐区给一次脉冲，用于清空有效状态；不能与第一像素同时占用 IP 清零 |
| data_req | 输出1 | 正常运行时等于 src_de，连接 RD1 |

必须保证在同一个消费上升沿之前：gray8、src_de、src_x/y、src_hs/vs 都代表同一位置。不能把先寄存的 DE、未寄存的 x 和另一拍 HS 随意拼接。

不要以暂停 data_req 的方式等待算术流水。若发生 FIFO 空，单独报告供数异常，按第8章恢复。

### 4.2 gray_line_buffer：两行历史缓存封装

参数：LINE_PIXELS=800、PIXEL_WIDTH=8。该封装不额外寄存抽头，不增加未计算的延迟。

| 端口 | 方向/位宽 | 约定 |
|---|---|---|
| clk、rst_n | 输入各1 | 像素时钟、复位 |
| frame_prepare | 输入1 | 帧前消隐区清除/失效化控制 |
| pixel_en | 输入1 | 正常情况下接 src_de；只在有效像素时移位 |
| gray_in | 输入8 | 当前像素 |
| row1、row2 | 输出各8 | 最近一行和前两行的抽头值；在消费上升沿前读取，与当前像素同列 |

下层 gray_line_shift / ALTSHIFT_TAPS 接口：clock、clken、aclr、shiftin[7:0] 为输入，taps[15:0]、shiftout[7:0] 为输出。参数 number_of_taps=2、tap_distance=800、width=8。row1=taps[7:0]，row2=taps[15:8]，shiftout 与最老抽头重复，可悬空。

IP 在上升沿更新抽头；sobel_filter 在同一上升沿读的是更新前的抽头。正是这种配合使两个历史行与当前 gray_in 对齐。若在 wrapper 中又打一拍，当前行也必须补齐，同时重新推导总延迟。不得把“沿后观察到的抽头”与“同一沿前的输入”混用。

行存储逻辑容量=2×800×8=12800 bit，实际 M9K 占用按综合映射取整。九像素窗口另用72 bit寄存器。内容清零策略应服从实际生成 IP 支持；即使缓存内容不清零，帧内填充状态也必须让旧内容无效。

### 4.3 sobel_filter：合并窗口与核心算术

参数：IMAGE_WIDTH=800、IMAGE_HEIGHT=480、BINARY_MODE=1、THRESHOLD=128（初始试验值，单位为未经缩放的梯度幅值）、GAIN_SHIFT=2（幅值显示时的初始缩放值）。阈值与缩放需实图调整，128不是已上板验证的最优值。

| 端口 | 方向/位宽 | 功能 |
|---|---|---|
| clk、rst_n | 输入各1 | 时钟、复位 |
| frame_prepare | 输入1 | 清除窗口填充状态与valid，不让上一帧残留有效 |
| in_valid | 输入1 | 当前像素有效，正常接 src_de |
| in_x、in_y | 输入10、9 | 当前输入坐标，与 in_valid 同拍 |
| gray_in | 输入8 | 当前行同列像素 |
| row1、row2 | 输入各8 | 前一行、前两行同列像素，来自行缓存 |
| edge8 | 输出8 | 二值边缘或8位边缘强度，已经过第三级算术寄存 |
| edge_valid | 输出1 | edge8 对应真实完整3×3窗口；只覆盖内部像素 |
| edge_x、edge_y | 输出10、9 | edge8 对应的窗口中心坐标，随流水传递 |

edge_valid 与 TFT 的 DE 不是同一含义：前者说明完整窗口结果有效，后者说明面板正处于800×480有效区域。边框期间 TFT_DE 仍为高，但 edge_valid 为低，RGB必须置黑。

不另设 matrix_3x3 或 sobel_core 实例；内部九寄存器和三级运算见第5章。

### 4.4 video_output_align：同步对齐、黑边与输出

参数：CENTER_TO_RESULT=1060，IMAGE_WIDTH=800，IMAGE_HEIGHT=480。默认不在 edge8 后再增加 RGB 输出寄存器；edge8 已在第三级寄存。若增加一级，统一改为1061，并同步更新控制和仿真。

| 端口 | 方向/位宽 | 功能 |
|---|---|---|
| clk、rst_n | 输入各1 | 像素时钟、复位 |
| src_hs、src_vs、src_de | 输入各1 | 原始输入像素基准的控制信号 |
| src_x、src_y | 输入10、9 | 同一输入像素坐标，用于对齐验证及边框 |
| frame_prepare | 输入1 | 帧标志；清除缓存与延迟输出屏蔽要区分，不能每帧直接清空仍在排出的上一帧尾部 |
| edge8、edge_valid | 输入8、1 | Sobel 最终输出 |
| edge_x、edge_y | 输入10、9 | 中心坐标，用于断言匹配 |
| tft_rgb | 输出16 | 有效内部像素为 {edge8[7:3],edge8[7:2],edge8[7:3]}，其余为0 |
| tft_hs、tft_vs、tft_de | 输出各1 | 与最终像素同相位的同步及有效信号 |
| out_x、out_y | 输出10、9 | 延迟后的显示位置，便于边框和验证 |

功能可以使用同步移位延迟或等价的相位偏移扫描器实现。文档以明确的时间关系定义接口，不强制使用1060级触发器。若坐标也直接移位，资源显著高于只移动3位同步信号；可重建坐标或采用 RAM 延迟线，任何替换都必须保持相同采样关系。

tft_clk 仍接33 MHz时钟路径，tft_pwm 沿用原背光控制。不要把时钟当普通数据移位延迟。

## 5. Sobel 运算、位宽与流水

### 5.1 窗口定义和更新

窗口中心是 p22，而不是最后输入的 p33。对本次输入坐标(x,y)：

```text
p11=I(x-2,y-2)   p12=I(x-1,y-2)   p13=I(x,y-2)
p21=I(x-2,y-1)   p22=I(x-1,y-1)   p23=I(x,y-1)
p31=I(x-2,y)     p32=I(x-1,y)     p33=I(x,y)

中心坐标：(x-1,y-1)
```

窗口寄存示意（仅说明数据移动，复位、坐标、有效流水另行实现）：

```verilog
reg [7:0] p11, p12, p13;
reg [7:0] p21, p22, p23;
reg [7:0] p31, p32, p33;

always @(posedge clk) begin
    if (in_valid) begin
        {p11,p12,p13} <= {p12,p13,row2};
        {p21,p22,p23} <= {p22,p23,row1};
        {p31,p32,p33} <= {p32,p33,gray_in};
    end
end
```

合法窗口条件为 in_valid && in_x>=2 && in_y>=2，并且已经确认缓存属于本帧。行首前两次移位把上一行横向残留逐步冲走，这两个窗口必须无效。若对行首额外清零，不得同时丢失该行首像素的装载。

### 5.2 卷积核与物理意义

```text
Gx核                     Gy核
-1   0  +1               -1  -2  -1
-2   0  +2                0   0   0
-1   0  +1               +1  +2  +1
```

```text
Gx = (p13 + 2*p23 + p33) - (p11 + 2*p21 + p31)
Gy = (p31 + 2*p32 + p33) - (p11 + 2*p12 + p13)
M  = abs(Gx) + abs(Gy)
```

Gx反映左右灰度变化，Gy反映上下变化；整体符号反转不影响绝对值幅值。使用绝对值和近似梯度强度，避免平方与开方。中心像素 p22 虽然在两个核中的权重为0，仍用于窗口位置定义和标签验证。算法公式参考 [OpenCV Sobel 官方说明](https://docs.opencv.org/4.x/d2/d2c/tutorial_sobel_derivatives.html)。

### 5.3 位宽与溢出

| 信号 | 范围或安全界 | 建议位宽 |
|---|---|---|
| 每个像素 | 0～255 | 8位 unsigned |
| 2×像素 | 0～510 | 至少9位 unsigned |
| 一侧加权和 | 0～1020 | 至少10位 unsigned |
| Gx、Gy | -1020～+1020 | 11位 signed |
| abs(Gx)、abs(Gy) | 0～1020 | 10位足够；实现可统一11位unsigned |
| M | 用安全上界2040分配，不宣称两方向最大值一定同时可达 | 11位 unsigned |
| THRESHOLD | 与M相同尺度 | 11位 unsigned |
| edge8 | 0～255 | 8位 unsigned |

必须先扩展位宽，再移位、相加、相减。不能先在8位表达式中求2*p23，再赋给11位变量来补救已经发生的截断。

示意：先将每个像素扩展为 $signed({3'b000,pij}) 的11位正数，再进行 <<<1 和加减。也可以先分别求两个10位无符号侧和，再各补一个符号0进行11位有符号相减。所有中间量的 signed/unsigned 应显式定义。

### 5.4 输出方式

二值模式：edge8=(M>=THRESHOLD)?8'hFF:8'h00。阈值比较直接针对11位原始幅值，不能误用缩放后的8位亮度阈值。

强度模式：先令 Q=M>>GAIN_SHIFT，再 edge8=min(Q,255)。使用饱和，禁止简单取 M[7:0]，否则强边缘会模256回绕变暗。SHIFT=2仅为起始显示增益。

纯色区域内部应接近0；黑白竖直台阶的一方向梯度可达1020；斜边常使两个方向同时非零。噪声和纹理也会产生边缘，第一版不增加独立高斯滤波，以保持结构和延迟清晰。

### 5.5 精确流水安排

| 阶段 | 在该沿写入的寄存器 | 读取的旧寄存器 | 有效与坐标 |
|---|---|---|---|
| W | p11～p33 | IP旧抽头、当前gray_in、旧横向像素 | win_valid、center_x=x-1、center_y=y-1 |
| A1 | gx_reg、gy_reg | 上一沿完整窗口 | v1、x1、y1取旧W元数据 |
| A2 | magnitude_reg | 旧gx_reg/gy_reg | v2、x2、y2取旧A1元数据 |
| A3 | edge8 | 旧magnitude_reg | edge_valid、edge_x/y取旧A2元数据 |

所有状态更新使用非阻塞赋值。不能在同一 always 中写 gx_reg<=... 后，又把新计算的gx_reg视为立即可供 magnitude 使用；后者读到的是旧值。

W只在输入像素有效时移位。A1～A3及其valid流水每个像素时钟都推进，消隐时输入无效气泡。若将整个算法也由 src_de 门控，行尾结果会被延迟到下一行，1060个连续时钟的关系失效。

从W沿后窗口就绪，到A3沿后结果就绪，经过3个时钟间隔；若从沿前输入描述结构，W+A1+A2+A3可称4个寄存阶段。必须区分“寄存阶段数”和两个已采样时刻间的“时钟间隔数”。

## 6. 中心像素到运算结果的延迟推导

### 6.1 延迟的三个来源

1. 空间前视：3×3中心卷积必须看到中心像素下面一行、右边一列。中心先到达时，右下邻居尚未被读出，算术再快也不能使用未来数据。
2. 抽头与横向窗口：历史行保存在IP中，当前行和两个旧抽头在W沿装入九像素寄存器。必须按实际IP沿前/沿后行为确定同列对应。
3. 运算寄存：窗口形成后还需要A1、A2、A3三个时钟间隔。若再次寄存显示数据，还要再加1。

本文从SDRAM读FIFO输出被像素时钟采样开始计数，不包含摄像头曝光、DVP采集、SDRAM排队、读写帧不同步等系统总延迟。

### 6.2 坐标推导

中心像素为I(xc,yc)。完整窗口最后一个像素是I(xc+1,yc+1)。同列的下一行比当前行晚一整行1056个时钟，再向右一列晚1个时钟。

```text
中心 I(xc,yc) 被采样：                 C
右下 I(xc+1,yc+1) 被采样并装入窗口：   C + 1056 + 1
窗口 W 沿：                            C + 1057
A1 梯度沿：                            C + 1058
A2 幅值沿：                            C + 1059
A3 最终结果沿：                        C + 1060
```

这里1057已经包含本结构的IP抽头与窗口采样配合，不能再人为增加一个“窗口级”。关系只对可形成完整窗口的内部像素成立；边框由输出模块补黑。

### 6.3 为什么不是800+1+3

IP只保存有效像素，因此 tap_distance=800；但两个相邻图像行在实际时间上间隔1056个像素时钟，中间还有256个消隐时钟。

```text
行缓存距离：800 个有效像素样本
实际时间距离：800+256=1056 个连续像素时钟
总延迟：1056+1+3=1060 个连续像素时钟
```

既不能让缓存用800间距却在消隐也移位，也不能用804个时钟去延迟TFT控制。两种错误都会让数据与行列错位。

### 6.4 三抽头旧方案为什么更慢

若三个历史抽头全部用来组成窗口，当前行不直接参与：输入行y时，窗口三行来自y-3、y-2、y-1，中心落在y-2；较推荐方案额外落后一行。

| 结构 | 窗口中心就绪 | 三级算术后 | 再加显示寄存器 |
|---|---:|---:|---:|
| 两抽头+当前行 | C+1057 | C+1060 | C+1061 |
| 三历史抽头 | C+2113 | C+2116 | C+2117 |

少一个历史抽头，减少1056个连续时钟，约32微秒，同时节省800×8=6400bit逻辑缓存容量。最终推荐两抽头+当前行。

### 6.5 换算为时间及参数化

```text
Tpixel = 1/33MHz ≈ 30.303ns
Lwindow = H_TOTAL+1 =1057周期 ≈32.030微秒
Larithmetic =3周期 ≈0.091微秒
Lresult =1060周期 ≈32.121微秒
```

通式：Lresult=H_TOTAL+1+ARITH_STAGES+EXTRA_STAGES。仅适用于本文同样的两抽头/当前行采样结构，不是所有行缓存实现的通用公式。

若灰度模块增加寄存器、IP封装增加寄存器或输出加一级，数据和对应元数据均须重新核算。输入在 C 这个采样沿前已经满足建立时间；组合灰度的传播延迟不另计整周期，但影响时序可实现性。

### 6.6 能否进一步减少

将算术三级压成两级，总计1059；压成一级，总计1058，但需重新验证逻辑时序。节省每一级仅约30ns，远少于减少一行带来的32微秒。

当输入仍按光栅顺序、每像素一拍读取时，一行加一列的未来邻域需求无法靠删寄存器消除。提前从SDRAM预取下一行、改变读取调度或增加中间结果缓存，可以把等待移到TFT有效输出之前，但属于另一种调度架构，不能直接套用1060，也不等于去掉了邻域依赖。

## 7. Sobel 与 TFT 的对齐方法

### 7.1 保留扫描参数，改变输出相位

800×480、HS/VS脉宽、前后肩、每行1056、每帧525均不改变。推迟的是对应图像位置的输出同步相位。输入取数时序继续按原扫描运行。

以原始中心像素在C沿采样为锚点，在C+1060沿之后，输出控制应指向同一中心位置，且edge8也已寄存为该位置结果。不能把未来输入位置(x+1,y+1)的DE当成中心像素的输出DE。

### 7.2 控制线和坐标的严格采样约定

建议将对齐模块的参考元数据在C沿采样为meta[0]，定义meta[k]在后续每个上升沿由meta[k-1]传递。则meta[1060]在C+1060沿后与edge8对齐。

```verilog
// 时序定义示意，尚非工程实现；大深度实际可用RAM或等效计数器。
reg [META_W-1:0] meta [0:CENTER_TO_RESULT];
always @(posedge clk) begin
    meta[0] <= source_meta; // 在C采样，与输入像素对应
    for (integer k=1; k<=CENTER_TO_RESULT; k=k+1)
        meta[k] <= meta[k-1];
end
```

这段例子含1061个寄存位置，但从C这个已采样时刻到输出是1060个时钟间隔。另一些delay模块把参数D定义为D级寄存器，沿前输入在C采样后到C+D-1沿就输出。两种命名都可用，但必须用时间戳断言校准，不能只看参数名 LATENCY。

现有 Disp_DE/HS/VS 的产生拍次及原RGB输出拍次没有统一为上述合同。实施时先重构/校准基准，再决定移位数组索引，不能机械地在现有video_*后接“1060级”就宣布对齐。

### 7.3 输出门控与边框

以out_x/out_y表示已延迟后的显示坐标：

```text
border = out_x==0 || out_x==799 || out_y==0 || out_y==479
TFT_DE = delayed_src_de
RGB = 0，若 !TFT_DE 或 border 或 !edge_valid
RGB = {edge8[7:3],edge8[7:2],edge8[7:3]}，其余情况
```

对于内部显示像素，必须验证 edge_valid=1，且(edge_x,edge_y)==(out_x,out_y)。内部缺valid应在仿真报错，不能一直填黑把错误掩盖。

整个有效区仍每行800个DE周期，不能直接用edge_valid作DE，否则每行会缩为798个像素，且顶底行消失，面板时序不完整。

### 7.4 是否保留最后一级RGB寄存

推荐第一版由A3寄存edge8，输出对齐模块只作数据选择和位拼接，不再经过旧disp_driver的RGB寄存器。其数据/控制目标为C+1060。

若为I/O时序增加最终寄存器，则数据、HS、VS、DE、必要坐标统一多一拍，目标C+1061。若仅RGB多打一拍，图像会偏移；若只延迟控制，数据也会错位。

边框选择的组合路径、RGB/DE相对tft_clk引脚的建立保持关系仍须检查。内部对齐成功不代表外部TFT接口已经满足时序；具体采样极性应依据所用屏幕和现有板级连接确认，不在本文中凭空改变像素时钟相位。

### 7.5 不延迟的信号

- data_req / RD1：原扫描取数节奏。
- IP与算法工作时钟clk_tft：保持33MHz。
- tft_clk：使用合法的时钟路径，不用普通逻辑移位时钟。
- 摄像头采集、写FIFO、SDRAM控制器时钟：保持当前配置。

### 7.6 对齐实现的资源选择

只延迟HS/VS/DE三位信号，参考结构逻辑存储约3×1061=3183bit；若额外把10位x、9位y全部逐级保存，则约22×1061=23342bit，实际还要加帧标记等。采用RAM延迟或相位偏移计数器可降低触发器消耗。

第一版可优先使用容易验证的明确延迟实现，再据综合结果优化。无论实现形式如何，都必须保留相同周期断言；不能为省资源悄悄改变DE或帧周期。

## 8. 消隐、边界、帧切换与异常

### 8.1 水平消隐

每行256个消隐时钟期间：行缓存和九像素窗口保持，A1～A3和同步对齐继续运行，valid注入0。行尾的最后一个内部中心像素x=798由输入x=799形成，之后三级流水可能跨入原始消隐区，必须允许它排出。

### 8.2 每帧启动

1. 上电时清空控制/valid，使输出安全。
2. frame_prepare在第一有效像素前的消隐区发出，完成IP清零或有效状态失效化，不能占用首像素采样沿。
3. 读入前两行期间没有完整窗口，但延迟后仍输出完整扫描和黑色顶部边框。
4. 输入(y=2,x=2)第一次形成中心(y=1,x=1)的有效窗口。
5. 当前帧的底部边框没有完整邻域，按延迟后的坐标填黑，无需读入下一帧来伪造底部邻居。

### 8.3 帧尾不能粗暴复位所有流水

行缓存失效化和上一帧结果排出是不同事件。不能在原始最后一个像素之后立即复位所有A1～A3及控制延迟线，否则可能删除仍在路上的结果。选择已有足够空白的frame_prepare时刻，或分开处理缓存更新和输出排空，并用整帧测试证明。

第一帧启动可能有无效内容，必须以valid/坐标屏蔽；不要假设上电RAM恰好清零就可省略窗口有效管理。

### 8.4 FIFO空读与图像撕裂

固定光栅方案依赖SDRAM读FIFO供数充足。如果空读，禁止在“扫描继续、缓存暂停”之后继续宣称行间距仍为800个正确样本。第一版建议检测RD1_EMPTY与src_de的重叠，记录underflow，屏蔽本帧结果，下一帧重建缓存和位置。

仅在顶层加RD1=!empty&&src_de并不能自动恢复正确图像。摄像头与TFT不同帧率、单帧地址循环造成的撕裂也独立于Sobel，需要后续按实际表现设计帧缓冲策略。

## 9. 实施顺序和验证标准

### 9.1 拟修改/新增文件

| 文件 | 操作 |
|---|---|
| rtl/ov5640_sdram_hdmi_tft.v | 替换显示路径连接；接出读FIFO空状态；保留顶层端口 |
| rtl/vga/disp_driver.v 或新 tft_timing_gen.v | 分离原始扫描与RGB输出；校准src_de/x/y/同步合同 |
| rtl/image_process/rgb565_to_gray.v | 复用，原则上不修改 |
| rtl/image_process/gray_line_buffer.v | 新增IP封装，不额外打一拍 |
| ip/gray_line_shift.v、相应.qip等 | 生成两抽头、800间距、8位IP |
| rtl/image_process/sobel_filter.v | 新增九像素窗口+三级Sobel |
| rtl/image_process/video_output_align.v | 新增控制对齐、边框和输出 |
| ov5640_sdram_hdmi_tft.qsf | 登记新增RTL/IP；防止重复加入IP库文件 |
| verification/sobel 下测试文件 | 新增功能与整帧测试，不加入综合源文件 |
| 副本修改说明.md | 记录本副本与灰度基准的差异、验证及编译结果 |

不得为加入Sobel而修改原始资料工程或灰度工程。

### 9.2 单元验证

- 灰度模块：沿用65536个RGB565全输入检查。
- 行缓存：用行号/列号或唯一标签验证row1/row2同列、行首行尾、消隐停移、帧间失效。
- 窗口：九个像素逐个比对软件/测试平台参考二维数组，不能只检验p22。
- Sobel：常量图、竖直台阶、水平台阶、斜边、孤立点、棋盘、随机图，逐像素比对Gx/Gy/M/edge8，覆盖正负梯度和饱和阈值边界。
- 非二值输出：验证缩放、饱和，不发生8位回绕。

### 9.3 整帧集成验证

至少连续两帧，验证：每帧480个有效行，每行800个DE周期；内部798×478个完整窗口结果；首帧预热；上下左右黑边；跨行消隐；帧切换不混用旧行；HS/VS宽度与周期不变。

对内部像素建立断言：输出标签对应输入中心C，结果在C+1060沿出现；可选最终输出寄存器存在时为C+1061。坐标、valid和数据逐一匹配。边框只能是预期的一圈，不允许整行/整帧被填黑却通过测试。

原有时序标签测试只模拟9行且无完整垂直帧切换，不满足这些整帧验收条件。

### 9.4 Quartus 与上板

加入完整RTL后在本目录重新全编译，确认0error、目标器件及引脚正确，检查实际IP映射和新增路径时序。此前按用户要求暂不处理SDC缺失，但既有 Timing requirements not met 仍存在；因此“编译成功”“生成SOF”不能写成“时序已收敛”。

按阶段上板：先灰度旁路基准，再验证窗口/坐标测试图，再输出强度边缘，最后二值化调阈值。每次编译和下载记录SOF哈希，防止误下载继承的灰度SOF。当前output_files中的文件仍是复制来的灰度版本。

## 10. 资源、限制与证据

### 10.1 估算

新增行缓存逻辑容量12800bit、窗口72bit，算术为加减、移位、取绝对值和比较，不要求乘法器或除法/开方单元。控制延迟资源按实际实现确定，不把逻辑容量直接等同于最终M9K数。

当前复制的灰度工程历史报告为1015个LE、622个寄存器、22528bit RAM、2个PLL。该数值不包含未来完整Sobel，不作为未来资源报告。

### 10.2 已有本地证据

| 证据 | 已验证 | 尚未验证 |
|---|---|---|
| verification/grayscale/simulation.log | 灰度65536输入、0error/0warning | 完整Sobel |
| verification/latency_analysis/simulation.log | 三历史抽头+三级算术标签传播，4788次内部检查，2116/2117周期 | 完整算术、整帧边界 |
| verification/latency_analysis/simulation_two_taps.log | 两抽头+当前行，5586次内部检查，窗口1057、结果1060、额外显示寄存1061 | 完整算术、帧切换、真实TFT同步与接口 |
| verification/latency_analysis/altshift_taps_model.v | 来自本机Quartus13的未改动单模块行为模型 | 尚未生成的最终IP封装/布局布线 |

本地标签仿真用32位标签代替8位亮度来追踪来源，测试时钟为10ns周期；其周期数量不依赖这个仿真频率。文档中的微秒值按目标33MHz换算，不代表该标签测试实际使用了33MHz，也不证明硬件最高频率。

### 10.3 参考资料与结论来源

- [OpenCV：Sobel Derivatives](https://docs.opencv.org/4.x/d2/d2c/tutorial_sobel_derivatives.html)：用于核对卷积核和绝对值和近似。本设计的位宽、接口和流水划分由本工程需求推导。
- [Altera：RAM-Based Shift Register ALTSHIFT_TAPS IP Core User Guide](https://docs.altera.com/api/khub/documents/_0dwmnCYjUqhV74S4~CjAQ/content)：用于核对抽头、间距和RAM存储概念。手册版本为14.0；本机Quartus13使用MegaWizard，具体沿关系以本机模型及最终生成封装为准。
- 本机模型源：D:\gx2026\software\quartus13\quartus\eda\sim_lib\altera_mf.v 中 altshift_taps 模块。
- 生产RTL、QSF与本地测试日志：均来自本Sobel副本，1060/2116等周期数由上述具体连接与标签测试支持，并非官方IP手册给出的通用延迟常数。

## 11. 既有叶子模块接口声明附录

以下从当前副本源码自动提取第一模块的端口声明，保留宏及参数表达式，方便实施时逐项核对。此附录描述现有代码，不覆盖第4章拟新增接口。所有厂商IP内部层级由相应库实现。

### rtl\ov5640_sdram_hdmi_tft.v

```verilog
input 			clk,
input 			rst_n,
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
output			camera_sclk,
inout				camera_sdat,
input				camera_vsync,
input				camera_href,
input				camera_pclk,
output			camera_xclk,
input 	[7:0]	camera_data,
output			camera_rst_n,
output			camera_pwdn,
output  [15:0]  tft_rgb,
output          tft_hs,
output          tft_vs,
output          tft_clk,
output          tft_de,
output          tft_pwm
```

### ip\pll.v

```verilog
input	  inclk0;
output	  c0;
output	  c1;
output	  c2;
output	  c3;
output	  c4;
```

### ip\pll_hdmi.v

```verilog
input	  inclk0;
output	  c0;
output	  c1;
```

### rtl\camera_init\camera_init.v

```verilog
input Clk;
input Rst_n;
output reg Init_Done;
output camera_rst_n;
output camera_pwdn;
output i2c_sclk;
inout i2c_sdat;
```

### rtl\camera_init\ov5640_init_table_rgb.v

```verilog
input clk;
input [(ADDR_WIDTH-1):0] addr;
output reg [(DATA_WIDTH-1):0] q;
```

### rtl\camera_init\ov5640_init_table_jpeg.v

```verilog
input clk;
input [(ADDR_WIDTH-1):0] addr;
output reg [(DATA_WIDTH-1):0] q;
```

### rtl\camera_init\i2c_control.v

```verilog
input Clk;
input Rst_n;
input wrreg_req;
input rdreg_req;
input [15:0]addr;
input addr_mode;
input [7:0]wrdata;
output reg[7:0]rddata;
input [7:0]device_id;
output reg RW_Done;
output reg ack;
output i2c_sclk;
inout i2c_sdat;
input [5:0]Ctrl_Cmd;
input [5:0]Ctrl_Cmd;
input [7:0]Wr_Byte_Data;
```

### rtl\camera_init\i2c_bit_shift.v

```verilog
input Clk;
input Rst_n;
input [5:0]Cmd;
input Go;
output reg[7:0]Rx_DATA;
input [7:0]Tx_DATA;
output reg Trans_Done;
output reg ack_o;
output reg i2c_sclk;
inout i2c_sdat;
```

### rtl\DVP_Capture.v

```verilog
input Rst_n;
input PCLK;
input Vsync;
input Href;
input [7:0]Data;
output reg ImageState;
output DataValid;
output [15:0]DataPixel;
output [11:0]Xaddr;
output [11:0]Yaddr;
```

### rtl\Sdram_Control_4Port\Sdram_Control_4Port.v

```verilog
input                   CTRL_CLK;
input                   RESET_N;
input   [`DSIZE-1:0]    WR1_DATA;
input							WR1;
input	[`ASIZE-1:0]		WR1_ADDR;
input	[`ASIZE-1:0]		WR1_MAX_ADDR;
input	[9:0]					WR1_LENGTH;
input							WR1_LOAD;
input							WR1_CLK;
output						WR1_FULL;
output	[15:0]			WR1_USE;
output  [`DSIZE-1:0]    RD1_DATA;
input							RD1;
input	[`ASIZE-1:0]		RD1_ADDR;
input	[`ASIZE-1:0]		RD1_MAX_ADDR;
input	[9:0]					RD1_LENGTH;
input							RD1_LOAD;
input							RD1_CLK;
output						RD1_EMPTY;
output	[15:0]			RD1_USE;
output  [11:0]          SA;
output  [1:0]           BA;
output  [1:0]           CS_N;
output                  CKE;
output                  RAS_N;
output                  CAS_N;
output                  WE_N;
inout   [`DSIZE-1:0]    DQ;
output  [`DSIZE/8-1:0]  DQM;
```

### rtl\Sdram_Control_4Port\Sdram_WR_FIFO.v

```verilog
input	  aclr;
input	[15:0]  data;
input	  rdclk;
input	  rdreq;
input	  wrclk;
input	  wrreq;
output	[15:0]  q;
output	  rdempty;
output	[9:0]  rdusedw;
output	  wrfull;
output	[9:0]  wrusedw;
```

### rtl\Sdram_Control_4Port\Sdram_RD_FIFO.v

```verilog
input	  aclr;
input	[15:0]  data;
input	  rdclk;
input	  rdreq;
input	  wrclk;
input	  wrreq;
output	[15:0]  q;
output	  rdempty;
output	[9:0]  rdusedw;
output	  wrfull;
output	[9:0]  wrusedw;
```

### rtl\Sdram_Control_4Port\control_interface.v

```verilog
input                   CLK;
input                   RESET_N;
input   [2:0]           CMD;
input   [`ASIZE-1:0]    ADDR;
input                   REF_ACK;
input							INIT_ACK;
input                   CM_ACK;
output                  NOP;
output                  READA;
output                  WRITEA;
output                  REFRESH;
output                  PRECHARGE;
output                  LOAD_MODE;
output  [`ASIZE-1:0]    SADDR;
output                  REF_REQ;
output                  INIT_REQ;
output                  CMD_ACK;
```

### rtl\Sdram_Control_4Port\command.v

```verilog
input                           CLK;
input                           RESET_N;
input   [`ASIZE-1:0]            SADDR;
input                           NOP;
input                           READA;
input                           WRITEA;
input                           REFRESH;
input                           PRECHARGE;
input                           LOAD_MODE;
input                           REF_REQ;
input							INIT_REQ;
input							PM_STOP;
input							PM_DONE;
output                          REF_ACK;
output                          CM_ACK;
output                          OE;
output  [11:0]                  SA;
output  [1:0]                   BA;
output  [1:0]                   CS_N;
output                          CKE;
output                          RAS_N;
output                          CAS_N;
output                          WE_N;
```

### rtl\Sdram_Control_4Port\sdr_data_path.v

```verilog
input                  CLK;
input                  RESET_N;
input   [`DSIZE-1:0]   DATAIN;
input   [`DSIZE/8-1:0] DM;
output  [`DSIZE-1:0]   DQOUT;
output  [`DSIZE/8-1:0] DQM;
```

### rtl\image_process\rgb565_to_gray.v

```verilog
input  wire [15:0] rgb565,
output wire [7:0]  gray8
```

### rtl\vga\disp_driver.v

```verilog
input ClkDisp;
input Rst_n;
input [`Red_Bits + `Green_Bits + `Blue_Bits - 1:0] Data;
output DataReq;
output [11:0] H_Addr;
output [11:0] V_Addr;
output reg Disp_HS;
output reg Disp_VS;
output reg [`Red_Bits - 1 :0]Disp_Red;
output reg [`Green_Bits - 1 :0]Disp_Green;
output reg [`Blue_Bits - 1 :0]Disp_Blue;
output reg Disp_DE;
output Disp_PCLK;
```
