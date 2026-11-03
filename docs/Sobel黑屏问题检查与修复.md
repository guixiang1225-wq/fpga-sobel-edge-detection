> 最新下载状态：2026-11-02 15:34:19：启动黑屏修复版Sobel SOF已通过USB-Blaster下载至EP4CE10F17，Configuration succeeded，0 errors / 0 warnings。保留M16每按一次+8、E15每按一次-8，初值128。SHA256：7D67C82FC50C8726F6B4A480712A7501BC8C941517303EE1E5E4FC4E56E499EA。日志：verification\sobel\download_20261102_153417.log。仅配置SRAM，实屏效果待用户确认。

# Sobel 全黑问题检查与修复

日期：2026-11-02。仅修改 D:/gx2026/project/camera_sdram_tft_sobel。
原资料工程、彩色工程和灰度工程未写入；灰度基准清单的全部文件 SHA256 复核一致。

## 已确认的代码缺陷

旧 sobel_video_pipeline 在复位后立即让 data_req=src_de；每当 src_de && fifo_empty，就将 underflow_sticky 永久置1，video_output_align 又以该信号强制 RGB 为0。阈值比较结果因此无法到达屏幕。

800×480、1056×525、33MHz 下，复位后约1.13ms开始第一次有效像素请求。
camera_init 的初始等待本身约21ms，之后还要进行 SCCB 初始化。
DVP_Capture 在初始化未完成时保持 ImageState=1，该信号连接 SDRAM 的 WR1_LOAD。
Sdram_Control_4Port 的仲裁条件要求 WR1_LOAD==0 且 RD1_LOAD==0，因此这段时间不会预取读数据，读FIFO仍为空。
旧代码会在正常启动阶段触发永久黑屏。只调阈值或再次复位无法消除这个启动条件。

这是此前加入的欠载保护与系统启动时序不匹配，不能归因为用户阈值设置。尚未测量板上内部信号，结论来自RTL逻辑与动态仿真复现。

## 修改的生产文件

| 文件 | 修改 |
|---|---|
| rtl/ov5640_sdram_hdmi_tft.v | 接出RD1_USE[15:0]，将有效低10位连接视频链路fifo_used |
| rtl/image_process/sobel_video_pipeline.v | 增加fifo_used[9:0]及stream_started；在帧起点且FIFO非空、占用数≥256时启动；读请求、行缓存使能及Sobel输入valid统一用门控后的data_req；欠载只对实际读请求检查 |

读FIFO的rdusedw在clk_tft域内产生，不直接采样其他时钟域的二进制计数值。该FIFO深512，使用额外MSB，计数范围0～512。

新启动顺序：

1. TFT保持正常HS/VS/DE扫描，图像输出为黑色；停止FIFO消费和行缓存推进。
2. 等待SDRAM实际预取至少256个像素，即一个RD1_LENGTH突发。
3. 等到frame_prepare（h=v=0的消隐区）置stream_started。
4. 该帧第一个有效像素才发出首次读请求，读取仍保留在FIFO首部的地址0像素。
5. 进入连续读流后，data_req与原始src_de相同；Sobel中心延迟仍为1060个像素时钟。

不能只等待fifo_empty变低就在活动行中间开启，也不能逐像素用!fifo_empty丢弃读请求，否则FIFO地址与(x,y)位置会错开。

运行期间真正发生读空时，仍保留故障锁存并屏蔽图像至全局复位；本修复针对正常启动误触发。
没有增加运行中自动重建SDRAM读地址的恢复机制。若启动后仍黑，需要进一步区分实际运行欠载、上游无图像和外部接口问题。

按键M16/E15、±8、初值128、消抖、摄像头方向、灰度公式、Sobel算术、显示时序参数及引脚分配不变。QSF无需更改。

## 动态验证

使用 ModelSim SE-64 2020.4、Quartus实际altera_mf.v与工程Sdram_RD_FIFO.v。

新增 verification/startup_black_screen/tb_startup.sv，同时实例化旧链路与修复链路，共享真实异步FIFO的show-ahead输出。FIFO仅由修复链路消费；旧链路用于观察启动空状态的锁存结果，未模拟完整摄像头或SDRAM器件电气时序。

- 前两个完整TFT扫描周期不供数，随后在活动帧中途开始以独立快时钟和256字突发预填充FIFO。
- 旧链路阈值设为0，仍锁存故障并一直输出黑色，复现“调阈值无效”。
- 修复链路等待到下个完整帧边界；启动前无读请求、不锁存故障。
- 首次消费对应(x=0,y=0)，读出的每一个像素都检查FIFO地址顺序。
- 两帧800×480，共768000个显示像素与独立Python纹理图参考结果逐一一致，其中635424个白色边缘像素。
- HS/VS/DE每周期检查；延迟保持1060周期；无FIFO读空或溢出。
- 新增仿真0 errors / 0 warnings。
- 原四帧二值与强度模式回归再次通过：1536000显示像素、1525776个九像素矩阵、1529600组历史行；故障锁存与复位恢复也通过，0 errors / 0 warnings。

原有回归将FIFO从第一个有效像素起视为一直可用，未覆盖摄像头初始化时的读空；旧故障测试只验证了锁存屏蔽本身。因此之前的通过结果不足以证明真实启动正常，本次补齐这一测试缺口。

复现命令：运行本工程 verification/startup_black_screen/run_modelsim.ps1 和 verification/sobel/run_modelsim.ps1。新增测试依赖已保存的 verification/sobel/input_rgb.hex 与 gold_binary.hex。

## Quartus结果及板卡状态

Quartus13全编译成功：0 errors / 50 warnings。1523个LE、839个寄存器、58594bit RAM、0乘法器、2个PLL。
日志：verification/sobel/compile_20261102_152647.log。已有SDC缺失及Timing requirements not met仍在；不据此次功能修复宣称时序收敛。

新SOF：output_files/ov5640_sdram_hdmi_tft.sof
SHA256：7D67C82FC50C8726F6B4A480712A7501BC8C941517303EE1E5E4FC4E56E499EA

本次尚未下载新SOF，也未确认修复后实屏。上次已下载、且用户报告黑屏的版本SHA256为 8CA4C99EFB2C56DD65A7579ABB9595A0D63C68AC48CED8A04B34962083B5CC23。
下载新版本应使用本工程 scripts/download_sobel.ps1，或Quartus Programmer选择上述新SOF。仅重新编译不会改变板上当前运行内容。

## 备份与变更记录

verification/startup_black_screen/before 保存本次修复前顶层、链路、旧回归、结果、SOF与哈希文件；before_sha256.json可用于核对。
sobel_video_pipeline_before.v仅为旧代码对比仿真，更改了模块名；没有加入QSF，不参与FPGA综合。
本目录新增测试、日志和本说明；根目录副本修改说明及相关实现文档已更新。
