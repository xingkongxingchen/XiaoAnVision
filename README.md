# 校安视界 · XiaoAnVision

基于安路 EG4S20BG256 的 HDMI 校园多媒体展示终端。支持本地图片与音频播放、两秒短片循环、交互控制及人工应急图声联动。


本包对应已完成 Flash 写入、独立校验与断电自启验收的完整设计。短片源规格为 **160×120、10 fps、20 帧，名义时长 2 秒**；显示端放大到 640×480。SW1 开启时循环播放并重启每轮配音，关闭后恢复校园宣教。图片、音频、字幕、参数调节、转场、缩略图、波形与人工应急功能均保留；运行期图像 CRC 诊断保留。

## 文件入口

| 目录或文件 | 用途 |
|---|---|
| `TD_Project/XiaoAnVision.al` | 安路 TD 图形界面工程，直接打开该文件 |
| `TD_Project/rtl/top.v` | FPGA 顶层，完整 RTL 及原有 IP 位于 `TD_Project/rtl/` |
| `TD_Project/constraints/` | HX4S20C 引脚与时序约束 |
| `TD_Project/scripts/build_layout.tcl` | 原始 TD 全流程构建脚本，含完整 HDL 文件清单 |
| `tools/Build.ps1` | 可指定 TD 安装路径的便携构建入口 |
| `TD_Project/sim/` | 测试平台、参考模型和仿真脚本 |
| `tools/Simulate.ps1` | 短片控制、语音及缩放仿真的便携入口 |
| `bitstream/campus_media_full.bit` | 与已固化文件逐字节一致的完整位流 |
| `panel/` | 串口屏 HMI 工程及 TFT 编译文件 |
| `media/tf_card/` | FAT32 TF 卡根目录所需图片、音频及低帧率短片示例素材 |
| `records/` | 已有实现报告、仿真结果、Flash 写入与后续实物验收记录 |
| `MANIFEST_SHA256.json` | 本提交包逐文件 SHA-256 清单 |

## 环境与构建

- 开发板：HX4S20C；器件：EG4S20BG256；顶层：`top`。
- 已验收实现使用 Tang Dynasty **V6.2.168116**。仿真记录使用 ModelSim **10.5b**。
- 建议解压到纯英文路径，例如 `D:\XiaoAnVision`。不要只提取单个 HDL 文件，需保留目录结构和配套加密 IP。
- 图形界面入口为 **`TD_Project/XiaoAnVision.al`**。在 TD 中使用 `File → Open Project` 打开它；工程引用均为相对路径，器件为 EG4S20BG256，顶层为 `top`。
- 若打开时出现私有参数非默认值提示，选择 **Cancel**，保留布局种子 29 与逻辑层级优化设置。详细步骤见 `docs/TD工程打开说明.md`。
- 原始 Tcl 全流程入口仍保留；PowerShell 入口只启动 TD 构建，不下载、不写入硬件。

在包根目录运行，工具路径替换为自己的实际安装位置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build.ps1 -TdCommand "D:\TD\bin\td_commands_prompt.exe" -Tag submit01
```

该入口使用原始 RTL、99 个 HDL 构建输入及原始约束，采用 `area_prior`、映射策略 1、布局种子 29。新结果写入 `TD_Project/build/`，已有输出不会被覆盖；换一个 `-Tag` 可新建一次构建。脚本只在 setup/hold 余量非负且 TNS 为零时生成新位流。原始 Python 构建脚本也保留在源码中，其本机安装路径不作为本包的便携入口。

原生 `.al` 工程已在 Tang Dynasty V6.2.168116 中完成独立目录下的综合、布局和布线，并对新产生的布线数据库显式执行 `fix_hold`、最终时序检查及 bit 生成，99 个 HDL 输入、全部 RTL 及引脚/时序约束均保持不变。最终 Setup WNS 为 +0.122 ns，Hold WNS 为 +0.025 ns，Setup/Hold TNS 均为 0。完整日志和报告见 `records/native_rebuild/`。本次验证仅运行软件工具，没有下载到板卡或写入 Flash。

TD 默认路由流程会在切片占用超过 90% 时跳过内部 hold 修复；本设计切片占用为 92.40%，仅点击 GUI 默认全流程仍会得到负的 Hold WNS。因此完整重编译请使用 `tools/BuildNative.ps1`，它以 `.al` 为输入完成综合、布局和布线，再显式修复并检查最终时序，只有通过后才生成交付用新 bit。直接生成的 `XiaoAnVision_Runs/phy_1/XiaoAnVision.bit` 不能代替时序合格的结果。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\BuildNative.ps1 -TdCommand "D:\TD\bin\td_commands_prompt.exe" -Tag native01
```

新构建在独立的 `native_build_native01/` 副本内执行，合格输出为该目录下 `native_final/XiaoAnVision.bit`；不会改写提交包的归档 bit 或下载到板卡。

随包 `bitstream/campus_media_full.bit` 继续保留已经固化并通过实物验收的归档位流。本次新编译 bit 与归档文件并非逐字节相同，二进制配置区也存在差异，详细比较见 `records/native_rebuild/FULL_BUILD_AUDIT.json`。已有实物验收记录对应归档位流，本次新构建未单独上板。

## 仿真

短片控制、完整两轮语音与四倍缩放可分别运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Simulate.ps1 -VsimCommand "D:\ModelSim\win32aloem\vsim.exe" -Case control
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Simulate.ps1 -VsimCommand "D:\ModelSim\win32aloem\vsim.exe" -Case voice
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Simulate.ps1 -VsimCommand "D:\ModelSim\win32aloem\vsim.exe" -Case scaler
```

其他历史测试平台与结果按原样保留，部分 Python 批量脚本含原开发环境路径，运行前需配置安装位置。各用例的缩小规模、加速时钟和覆盖边界见对应源码与 `records/verification_summary.json`，不将单个模块仿真等同于完整硬件验收。

## 配套素材与串口屏

TF 卡采用 FAT32。将 `media/tf_card/` 中七个文件置于根目录：`PIC1.BMP`～`PIC4.BMP`、`AUDIO.PCM`、`ALERT.PCM`、`CLIP.BIN`。图片为 24 位非压缩 BMP，源码支持其不同源尺寸的最近邻适配。普通与应急音频是 48 kHz、16 位有符号小端、单声道无文件头 PCM；HDMI 输出 48 kHz 音频，左右声道同源。

`CLIP.BIN` 与本位流配对，含 512 字节头部、20 帧图像和 16000 个 8 kHz、8 位语音样本。不要将不同分辨率或帧率的短片文件与本位流混用。随包 PCM 为工程已有的演示素材，已经与其素材清单核对，并非本次从实物 TF 卡回读；若实物卡后来替换过同名音频，可按上述格式继续使用。

串口屏工程使用配套 USART HMI 编辑器打开 `panel/campus_autoconnect.HMI`，已编译文件为同目录 `.tft`。屏与 FPGA 的连接和命令格式见 `docs/使用说明.md`。不需要外部处理器参与图片解析、缓存或 HDMI 输出。

## 校验与固化文件对应关系

完整位流 SHA-256：
`9cd93289ff80836c85ac8390bd81eed5641eff19164ff116f81952128ccd7f93`

低帧率短片 SHA-256：
`9c4521f97c419fe75e9a6ee36e268a4120e3223fa8ec12acc1b90236be3c24e5`

这份位流文件名虽已改为提交用名称，文件内容与 Flash 写入记录及已验收发布归档完全一致。设备已固化时，上电会从 W25Q16 自动配置；本次打包不涉及再次下载或写 Flash。写入当时的工具结果及之后的断电自启验收分别保存在 `records/flash/` 中。

本包保留已有 IP 的加密形式、版权头与原始源码，不包含 TD、ModelSim 或串口屏编辑器的安装程序。
