# astonc / Adreno 740 GPU 适配评估

2026-10-28 静态代码研究 + PJE110 真机只读检查。尚未在 HakiOS 上执行 GPU 测试。

结论：值得作为单独的驱动移植项目推进；不能直接接上 hakios-metal 就获得 GPU 加速。
建议先点亮 A740 并完成写内存测试，再做 GLES，最后评估 Metal shaders 与桌面合成。

## hakios-metal 提供什么

研究版本：`652685f8af6cd14e3c0a3308be7a79a912628504`。
它主要实现用户态 buffer、queue、command buffer、copy/fill 及 metallib 解析。
`src/iokit_transport.cpp:62` 依赖内核已经提供 `HakiosGPU` 服务，不能替代 GMU / GPU 内核驱动。
README 明确说明 shaders 未接通，架构图仍以 Adreno 660 为例。
本机运行 `make test`：21 项通过，但使用 fake GPU，不能据此声称 A740 真机加速可用。

参考：[hakios-metal 固定版本](https://github.com/oosexgang/hakios-metal/tree/652685f8af6cd14e3c0a3308be7a79a912628504)。

## 真机已确认的资源

读取原厂 Android 16 + KernelSU Next 的 PJE110，未写 sysfs、加载固件或重启。

| 项目 | 实读结果 |
|---|---|
| GPU | Adreno740v2 |
| GPU compatible | qcom,adreno-gpu-gen7-2-1 |
| GMU compatible | qcom,gen7-gmu |
| GMU reg | 0x3d68000 / 0x37000 |
| PDC reg | 0xb280000 / 0x10000 |
| AO reg | 0x3d40000 / 0x10000 |
| GPU SMMU | 0x3da0000 / 0x40000 |
| GPUCC | 0x3d90000 / 0xa000 |
| GMU 固件 | /vendor/firmware/gmu_gen70200.bin，66844 B |
| SQE 固件 | /vendor/firmware/a740_sqe.fw，76724 B |
| zap | a740_zap.mdt，4044 B；a740_zap.b02，3896 B |

原厂目录没有 README 所说的 `a740_gmu.bin`。固件必须按真实格式、目标地址和对应版本加载，
不能通过改名套用 A660 的加载过程。厂商 DT 与主线驱动的资源视图不同，必须核对 reg-names。

## 与当前内核的差距

当前 `hakios.adreno.c` 针对 redwood / Adreno 642L，使用 A660 系列固件、
chip ID `0x06030500`、GMEM 512KiB，及旧 GPUCC / GMU 序列。
A740 是 Gen7 第二代，主线表指定 GMEM 3MiB、不同的 SQE / GMU / zap 固件及启动配置。
旧驱动 GPUCC 的 CX / GX 偏移为 0x106c / 0x100c，SM8550 则为 0x9108 / 0x905c。

SM8550 主线 GPUCC 使用 `gdsc_gx_do_nothing_enable` 处理 GX power_on，
GX 电源状态不能只靠旧驱动写 GDSC 强行打开；需要正确的 GMU 启动、HFI / RPMh 和相关时钟。
厂商 DT 的 CX / GX 地址 0x3d99108 / 0x3d9905c 与 SM8550 偏移一致。

当前 astonc 的公开 port/、scripts/ 未发现 A740 专用实现；README 的“CX 已开”是作者报告，
不能视为本次已复现的结果。hakios-metal 链接的 `oosexgang/hakios` 公开访问返回 404，
其中的 `HakiosMetal.m` 插件在当前公开 hackios-xnu-kernel 里也未找到，完整接入还缺这部分。

现有驱动的 `gpu=1` 平台检查只比较 `soc base=0x00400000`，astonc 也满足这个条件，
不足以阻止错误使用旧寄存器。基础体验流程保持 GPU 关闭。

参考：[现有 HakiOS GPU 驱动](https://github.com/oosexgang/hackios-xnu-kernel/blob/88513176b1e96ecf0b764cd62c6f4e6ac71345e3/xnu/files/bsd/dev/hakios.adreno.c)、
[Linux A740 配置](https://github.com/torvalds/linux/blob/v6.17/drivers/gpu/drm/msm/adreno/a6xx_catalog.c)、
[SM8550 GPUCC](https://github.com/torvalds/linux/blob/v6.17/drivers/clk/qcom/gpucc-sm8550.c)、
[GMU 驱动](https://github.com/torvalds/linux/blob/v6.17/drivers/gpu/drm/msm/adreno/a6xx_gmu.c)。

## 建议验收顺序

1. 建立独立的 A740 平台分支，整理 DT、固件哈希、时钟与电源表。
   完成 CX、GMU 内存、HFI / RPMh，验收到 GMU 启动、GX 状态合理、RBBM 可读。
2. 配置 SMMU、固件认证 / 加载、SQE 和 ring，验收到 GPU 写回固定内存、fence 完成，
   且能正常停机和再次运行。
3. 复用 HakiosGPU 的 IOKit / msm ABI，运行 hakios-metal-probe 的 copy/fill 和队列测试，
   然后接 Mesa Freedreno、GLES 三角形、IOSurface / EAGL，验证 A7xx 参数与图像正确性。
4. 最后推进 Metal shaders、AIR→NIR→ir3、render/compute pipeline 与 CoreAnimation。
   Blit 或 GLES 成功都不能替代 Metal 渲染验收。

以上难度判断是基于代码差异的工程推断，不是已经完成的驱动适配，也不承诺具体工期。
