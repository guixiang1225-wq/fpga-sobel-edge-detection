> 最新下载状态：2026-11-02 15:34:19：启动黑屏修复版Sobel SOF已通过USB-Blaster下载至EP4CE10F17，Configuration succeeded，0 errors / 0 warnings。保留M16每按一次+8、E15每按一次-8，初值128。SHA256：7D67C82FC50C8726F6B4A480712A7501BC8C941517303EE1E5E4FC4E56E499EA。日志：verification\sobel\download_20261102_153417.log。仅配置SRAM，实屏效果待用户确认。

# 最新状态：已修复启动读空导致的永久黑屏

2026-11-02：详见[黑屏检查与修复](Sobel黑屏问题检查与修复.md)。新SOF已全编译，尚未下载；按键说明见[按键阈值调节说明](按键阈值调节说明.md)。下方末尾保留历史下载记录。

# Sobel 项目实施与验证结果

日期：2026-11-02。工程：D:\gx2026\project\camera_sdram_tft_sobel。

## 1. 已实现的行为

本工程已集成 SDRAM 读出侧 Sobel，不再只是灰度副本。路径：RGB565读FIFO → 组合灰度 → 两历史行加当前行 → 合并九像素窗口与Sobel → RAM控制延迟 → TFT。

默认800×480、33MHz、白色边缘黑色背景，四周一像素黑边。阈值使用未缩放的 abs(Gx)+abs(Gy) >= 128。中心像素消费到结果输出为1060个连续像素时钟间隔（约32.121微秒），无额外RGB输出寄存器。

摄像头方向和RGB565存储格式保持。原资料工程、彩色及灰度副本未修改；彩色及灰度基准文件SHA256复核通过。

## 2. 文件变更

已有文件仅修改：
- rtl/ov5640_sdram_hdmi_tft.v：用sobel_video_pipeline替换灰度显示路径，接出RD1_EMPTY和RD1_USE；新增SOBEL_THRESHOLD和SOBEL_BINARY_MODE顶层参数。
- ov5640_sdram_hdmi_tft.qsf：加入新增RTL和IP的QIP。

新增生产文件：
- rtl/image_process/tft_timing_gen.v：光栅、像素有效和坐标。
- ip/gray_line_shift.v、gray_line_shift.qip：两抽头×800×8 ALTSHIFT_TAPS。
- rtl/image_process/gray_line_buffer.v：无额外寄存器的抽头封装。
- rtl/image_process/sobel_filter.v：九像素窗口及三级算术。
- rtl/image_process/video_output_align.v：22位元数据RAM延迟、边界与输出门控。
- rtl/image_process/sobel_video_pipeline.v：完整链路及空读保护。

旧disp_driver.v保留为历史源码，但不再被顶层实例化。未重构SDRAM控制器。verification/sobel/before保存改动前顶层和QSF，基准哈希也存放于verification/sobel。

## 3. 实际接口与时序

新增同步模块均使用clk_tft上升沿、低有效复位。默认水平128/88/800/40，垂直2/33/480/10，总计1056×525。

| 模块 | 实际输入 | 实际输出 | 功能 |
|---|---|---|---|
| tft_timing_gen | clk,rst_n | src_hs/src_vs/src_de，src_x[9:0]，src_y[8:0]，frame_prepare | 沿前像素位置，frame_prepare在h=v=0消隐区 |
| gray_line_shift | clock,clken,aclr,shiftin[7:0] | taps[15:0] | 两个历史行抽头 |
| gray_line_buffer | clk,rst_n,pixel_en,gray_in[7:0] | row1[7:0],row2[7:0] | taps低字节为前一行，高字节为前两行 |
| sobel_filter | clk,rst_n,frame_prepare,in_valid,in_x[9:0],in_y[8:0],gray_in/row1/row2各8位,threshold[10:0] | edge8[7:0],edge_valid,edge_x[9:0],edge_y[8:0] | 窗口中心与结果元数据同步流水 |
| video_output_align | clk,rst_n,src_hs/vs/de,src_x/y,edge8,edge_valid,fault | tft_rgb[15:0],tft_hs/vs/de,out_x[9:0],out_y[8:0] | 中心相位对齐及边框 |
| sobel_video_pipeline | clk,rst_n,key_up_n/key_down_n,rgb565[15:0],fifo_empty,fifo_used[9:0] | data_req,tft_rgb[15:0],tft_hs/vs/de,underflow_sticky | 集成新增模块 |

rgb565_to_gray继续使用原组合实现。上表为已实施版本；早期详细设计文档第4章是设计草案，接口差异以本表及生产源码为准。

## 4. Sobel 运算与延迟

p11/p12/p13来自row2横向移位，p21/p22/p23来自row1，p31/p32/p33来自gray_in。输入(x,y)的窗口中心为(x-1,y-1)。仅in_valid且x>=2、y>=2时窗口有效；帧前两行旧RAM内容不作为合法窗口。

Gx=(p13+2*p23+p33)-(p11+2*p21+p31)。
Gy=(p31+2*p32+p33)-(p11+2*p12+p13)。
M=abs(Gx)+abs(Gy)。

像素先显式扩展为11位signed，再移位和加减。Gx/Gy范围±1020；幅值按安全上界2040使用11位unsigned。A1寄存梯度，A2寄存幅值，A3寄存阈值或强度结果。算术和valid在每个时钟推进，包括消隐；窗口和行缓存只在有效像素推进。

中心像素在C消费：
- C+1057：右下邻居到达并形成窗口。
- C+1058：A1梯度。
- C+1059：A2幅值。
- C+1060：A3结果。

1057由整行1056个连续时钟加向右一个像素构成。行缓存间距800只数有效样本，不能代替整行时间。

输出元数据IP参数：number_of_taps=1、width=22、tap_distance=1061。按实际IP模型，它在C+1060沿后输出C采样的元数据，抽头之后不加寄存。保存{HS,VS,DE,X[9:0],Y[8:0]}，不是1060级普通触发器链。

TFT_DE保持每行800像素、每帧480行。edge_valid只表示内部798×478窗口，不能替代DE。边框、消隐、窗口无效或欠载故障时RGB为0。tft_clk保持33MHz，DataReq=src_de && stream_started；启动后跟随原始src_de，绝不反馈延迟DE。

## 5. 帧与异常策略

行RAM不在每帧清零，输入前两行会覆盖旧内容；y>=2才允许完整窗口。frame_prepare只清窗口和窗口valid；A1～A3与输出延迟不随帧粗暴清空，保证在途结果排出。多帧不同图像已验证无旧帧污染。

启动前等待FIFO至少256像素，并从下一帧起点开始读流，此期间空FIFO不锁存故障。运行期间出现data_req && fifo_empty时underflow_sticky锁存，后续图像屏蔽为黑色，HS/VS/DE继续。空读时保留位置槽，不以跳过样本伪装恢复；需要按板上复位键重新建立读流。本版不尝试未经验证的帧地址自动修复。正常运行不应空读。

## 6. ModelSim 验证

使用实际完整Quartus13 altera_mf.v，不使用自制行缓存替身。输入模拟show-ahead读FIFO的确定性像素供给；并非摄像头电气、SDRAM器件模型或完整跨域系统仿真。

四帧连续800×480：常量图、交替竖直台阶、交替水平台阶、确定性纹理。独立Python整数参考模型生成RGB565、灰度、二值与强度结果。两个生产视频链路实例分别验证二值和强度模式。
- 显示像素1536000，逐像素一致。
- 完整九像素窗口检查1525776次，历史行同列检查1529600次。
- 每帧显示384000像素，内部381444结果。
- 纹理帧阈值恰好等于128的样本1759，包含正负梯度。
- 欠载保护检查218804时钟。
- 复位后以非恒定纹理验证重新填充及恢复。
- HS/VS/DE逐周期对比理论光栅相位，中心坐标一致。
- 消隐输入故意给X，确认不进入窗口。
- ModelSim最终0 errors / 0 warnings。

启动延迟与真实异步FIFO的两帧768000像素回归也已通过，旧阈值0版本黑屏已复现，详见黑屏检查与修复文档。

复现：运行verification/sobel/run_modelsim.ps1及verification/startup_black_screen/run_modelsim.ps1。参考数据已保存，需要重新生成时运行generate_reference.py。日志：simulation.log、compile.log；统计：golden_stats.json、results.json。测试时钟10ns用于加速，1060周期换算微秒时使用目标33MHz，不把仿真频率当成硬件最高频率。

## 7. Quartus 与板卡状态

Quartus II 13.0.0 Build156最新全编译：0 errors、50 warnings。资源：1523/10320 LE（15%）、839寄存器、58594/423936 RAM bit（14%）、0嵌入式乘法器、2/2 PLL。

按用户此前要求保留SDC缺失；全工程仍报告Timing requirements not met，未实现时序收敛。本次功能验证不替代完整SDC与板级建立保持验证。

此前按键版已下载，用户报告调阈值仍全黑。本次已复现并修复启动错误，新SOF尚未下载，实屏仍待确认。

## 8. 使用与调整

工程入口：本目录ov5640_sdram_hdmi_tft.qpf。
新Sobel文件：output_files/ov5640_sdram_hdmi_tft.sof。
本次SOF SHA256：7D67C82FC50C8726F6B4A480712A7501BC8C941517303EE1E5E4FC4E56E499EA。

用Quartus打开工程完整编译，或运行scripts/compile.ps1。连接USB-Blaster并给板卡供电后，在Programmer选择本目录SOF执行Program/Configure，或运行scripts/download_sobel.ps1。脚本核对SOF哈希和单设备JTAG链；只配置SRAM，断电后丢失。

顶层SOBEL_THRESHOLD默认128：增大保留强边缘，减小显示更多纹理与噪声。SOBEL_BINARY_MODE=1为白边黑底，改为0显示边缘强度（M右移2位并饱和）。修改参数后重新编译，不使用旧SOF。

本版保留镜像/翻转设置。旧按键版的启动全黑已在新SOF中修复，必须下载新文件才能生效；单独复位旧版本不能修复启动逻辑。若反复欠载，应检查上游FIFO和SDRAM供数，不能靠删除保护掩盖丢像素。

## 最新下载记录

2026-11-02 14:35:12：按用户要求，经 USB-Blaster [USB-0] 将已验证 Sobel SOF 下载至 EP4CE10F17；Configuration succeeded，0 errors / 0 warnings。SHA256：E9CE4608DADB90E520C27321335F1AFBBE8DA44D7B2DB0A57B7D6D08CD17E6FE。日志：verification\sobel\download_20261102_143510.log。仅配置SRAM，未写Flash；实屏效果待用户确认。
