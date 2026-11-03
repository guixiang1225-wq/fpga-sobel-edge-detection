# 两端口 SDRAM 控制器

本版本由同级目录 `Sdram_Control_4Port` 精简而来，只保留 **WR1 写端口和 RD1 读端口**。原始四端口文件、工程顶层、QSF 和其他已有文件均未修改。

## 修改范围

- 删除 WR2、RD2 的外部端口、FIFO 实例、数据数量信号和地址寄存器。
- 删除第二路地址更新、调度分支和 LOAD 判断。
- 将两位的读写端口选择掩码缩减为一位，移除写数据的二选一选择器。
- 保留 WR1、RD1 的原有名称和位宽，方便使用原工程的信号连接。
- 为辅助模块、参数文件增加独立名称，允许新旧版本同时加入工程而不出现模块重名。

以下行为沿用原实现：

- 读优先于写；读 FIFO 数据不足一批时补充，写 FIFO 数据达到一批时写入。
- 两个 FIFO 均为 **512×16 位**；写 FIFO 的 show-ahead 为 OFF，读 FIFO 为 ON。
- 保留独立的写端口时钟、读端口时钟与 SDRAM 控制时钟。
- 保留起始地址、最大地址、每批长度、LOAD 清空和地址循环逻辑。
- 保留初始化、刷新、整页突发、数据采样、预充电和 DQM/OE 的原有控制时序。
- 参数文件内容与原文件完全相同；没有顺带修改原实现的时序参数或位宽。

## 文件

| 文件 | 作用 |
|---|---|
| `Sdram_Control_2Port.v` | 一写一读控制器，顶层模块名为 `Sdram_Control_2Port` |
| `control_interface_2port.v` | 命令译码、初始化、刷新定时 |
| `command_2port.v` | SDRAM 引脚命令、地址和输出使能 |
| `sdr_data_path_2port.v` | 原写数据通路 |
| `Sdram_WR_FIFO_2Port.v` | 512×16 位写 FIFO，仍使用 Altera `dcfifo` |
| `Sdram_RD_FIFO_2Port.v` | 512×16 位读 FIFO，仍使用 Altera `dcfifo` |
| `Sdram_2Port_Params.h` | 原参数文件的独立副本 |
| `Sdram_Control_2Port.qip` | 将本版本全部 RTL 文件加入 Quartus 工程 |
| `original_files_sha256.json` | 生成前原工程文件的 SHA-256 校验值 |
| `verification/` | 静态检查、对比仿真及验证结果；不加入综合工程 |

## 如何接入原工程

1. 在 Quartus 的工程文件设置中添加本目录的 `Sdram_Control_2Port.qip`。
2. 将原顶层实例的模块名由 `Sdram_Control_4Port` 改为 `Sdram_Control_2Port`。
3. 删除该实例中的所有 `.WR2...(...)`、`.RD2...(...)` 连接。
4. 其他连接保持原样。以下为原工程使用的完整连接示例。

此处只是接入说明；生成本版本时没有执行这些顶层修改。

```verilog
Sdram_Control_2Port u_sdram_control_2port (
    .CTRL_CLK       (clk_sdr_ctrl),
    .RESET_N        (rst_n),

    .WR1_DATA       (fifo_wrdata),
    .WR1            (fifo_wrreq),
    .WR1_ADDR       (0),
    .WR1_MAX_ADDR   (IMAGE_WIDTH * IMAGE_HEIGHT),
    .WR1_LENGTH     (256),
    .WR1_LOAD       (fifo_aclr),
    .WR1_CLK        (camera_pclk),
    .WR1_FULL       (),
    .WR1_USE        (),

    .RD1_DATA       (RGB_DATA),
    .RD1            (DataReq),
    .RD1_ADDR       (0),
    .RD1_MAX_ADDR   (IMAGE_WIDTH * IMAGE_HEIGHT),
    .RD1_LENGTH     (256),
    .RD1_LOAD       (!rst_n),
    .RD1_CLK        (clk_vga),
    .RD1_EMPTY      (),
    .RD1_USE        (),

    .SA             (sdram_addr),
    .BA             (sdram_ba),
    .CS_N           (sdram_cs_n),
    .CKE            (sdram_cke),
    .RAS_N          (sdram_ras_n),
    .CAS_N          (sdram_cas_n),
    .WE_N           (sdram_we_n),
    .DQ             (sdram_dq),
    .DQM            (sdram_dqm)
);
```

两端口指 FPGA 内部的一路写接口和一路读接口，仍共享一组 SDRAM 数据总线，不是增加了物理双端口能力。

## 验证

验证参照是原四端口控制器关闭 WR2、RD2 后的行为。辅助 RTL 除模块名、引用名称和参数文件名外保持原样。

运行静态检查：

```powershell
python ./verification/verify_sources.py
```

在有 Vivado Simulator 的 Windows 环境中运行逐周期比较：

```powershell
./verification/run_verification.ps1 -VivadoBin 'C:\Vivado\Vivado\2023.2\bin'
```

测试覆盖长度 256、64、8 和 0，使用不同的读写时钟，比较控制引脚、地址、有效写数据、读端数据、FIFO 状态和内部状态，并检查复位、LOAD、地址回绕及刷新。

对比仿真使用共同的简化 FIFO 行为模型和相同的 SDRAM 读数据激励，目的是验证精简前后行为一致；它不代替 Altera FIFO 的 CDC 验证、真实 SDRAM 芯片模型验证、Quartus 时序分析或开发板测试。综合时仅加入 QIP，不要将 `verification/dcfifo_model.v` 加入工程。
