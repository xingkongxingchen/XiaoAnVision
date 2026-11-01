# 安路 TD 工程打开说明

## 打开工程

1. 完整解压本提交包，建议使用纯英文目录，例如 `D:/XiaoAnVision`。
2. 启动 Tang Dynasty V6.2.168116，选择 **File → Open Project**，打开 `TD_Project/XiaoAnVision.al`。
3. 工程名称为 `XiaoAnVision`，器件为 **EG4S20BG256**，顶层模块为 **top**。
4. 如出现 “The values of the following private parameters are not default, do you want to revert them?”，选择 **Cancel**。这会保留布局种子 29 和 `logic_level_opt=on`，继续打开工程。
5. 工程中的 99 个 HDL 文件与原始构建脚本清单一致；引脚约束为 `constraints/hx4s20_key_slideshow.adc`，时序约束为同目录 `.sdc`。

工程引用采用相对路径。请保留 `rtl/`、`constraints/`、`assets/` 等目录结构，不要只复制单独的 `.al` 文件。

## 编译与已有位流

GUI 工程可用于查看设计层次、源码、约束与运行 TD 常规综合和实现流程。原始 Tcl 脚本位于 `TD_Project/scripts/build_layout.tcl`，便携构建入口是包根目录的 `tools/Build.ps1`，使用方法见 `README_提交说明.md`。

原始脚本包含逐阶段的路由控制、显式 hold 修复和时序门限检查。需要按已有构建流程执行时，使用该脚本入口。一次新的 GUI 或脚本构建结果均需重新查看资源和时序报告；工具版本及实现过程可能影响最终位流。

提交用位流保留在 `bitstream/campus_media_full.bit`，与已固化归档的 SHA-256 一致。源码、素材及此位流没有因新增 `.al` 文件而改变。

## 本次工程入口检查

- TD 图形界面从迁移目录打开工程，正确识别器件与 `top` 顶层。
- 在另一独立目录中，由 TD 原生 `open_project -single_run`、`elaborate -top top` 完成设计解析，并成功加载 `.adc` 与 `.sdc`。
- 工程源码清单与原 Tcl 清单逐项一致，共 99 个 HDL 构建输入，未引入高帧率试验版本。
- 原生 `.al` 工程已在 Tang Dynasty V6.2.168116 中完成独立目录下的综合、布局和布线，并对新产生的布线数据库显式执行 `fix_hold`、最终时序检查及 bit 生成，99 个 HDL 输入、全部 RTL 及引脚/时序约束均保持不变。最终 Setup WNS 为 +0.122 ns，Hold WNS 为 +0.025 ns，Setup/Hold TNS 均为 0。完整日志和报告见 `records/native_rebuild/`。本次验证仅运行软件工具，没有下载到板卡或写入 Flash。


## 原生工程完整重编译入口

TD 默认路由流程会在切片占用超过 90% 时跳过内部 hold 修复；本设计切片占用为 92.40%，仅点击 GUI 默认全流程仍会得到负的 Hold WNS。因此完整重编译请使用 `tools/BuildNative.ps1`，它以 `.al` 为输入完成综合、布局和布线，再显式修复并检查最终时序，只有通过后才生成交付用新 bit。直接生成的 `XiaoAnVision_Runs/phy_1/XiaoAnVision.bit` 不能代替时序合格的结果。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\BuildNative.ps1 -TdCommand "D:\TD\bin\td_commands_prompt.exe" -Tag native01
```

新构建在独立的 `native_build_native01/` 副本内执行，合格输出为该目录下 `native_final/XiaoAnVision.bit`；不会改写提交包的归档 bit 或下载到板卡。
