# astonc 体验准备（Mac + GitHub Actions）

目标设备：一加 Ace 3 / astonc / PJE110，原厂系统，16GB RAM，已解锁 BL。
上游实测环境是 PixelOS + SukiSU，原厂系统兼容性尚待验证。

## 构建与下载

工作流 `.github/workflows/experience.yml` 仅手动触发。
公开 fork 构建 UEFI / 内核；私有构建仓库额外生成并打包 iOS 用户态，提供完整体验包。
在 GitHub Actions 的 Build astonc experience 中点击 Run workflow。
若已有成功的 UEFI / loader / 内核，可将 `reuse_build` 填为对应的私人 Release 标签，
例如 `experience-40703818797-1`，将跳过 Mu-Silicium 源码拉取和 UEFI / 内核编译，
直接恢复产物并生成用户态。该模式仍需下载、解包 Apple 用户态文件。
完整构建成功后，在私有仓库 Releases 下载 `astonc-mac-experience.tar.part-*` 与
`PARTS-SHA256SUMS`。账号的 artifact 存储配额已满，因此私人产物改存 Release，
每个分片小于 2GiB。它们不会自动过期，体验后可自行删除该私人 Release。
先在分片目录校验并合并（校验文件中的路径带 out/，请将分片放入 out/ 子目录）：

```bash
shasum -a 256 -c PARTS-SHA256SUMS
cat out/astonc-mac-experience.tar.part-* > astonc-mac-experience.tar
mkdir -p /path/to/experience
tar -xf astonc-mac-experience.tar -C /path/to/experience
cd /path/to/experience
shasum -a 256 -c SHA256SUMS
python3 port/hackios-aston.py status
```

构建尚未完成前不要执行后面的启动步骤。流水线未经云端成功运行前，不能认为镜像已就绪。
工具链使用发行版 latest，实际下载的 SHA256、源码版本会写入 out/build-provenance.txt。
内核编译返回非零时保留日志，且要求存在新构建的 arm64 Mach-O 内核；仍需人工复核编译日志。

## 上机前

先备份手机重要数据，记录原厂系统完整版本。不要重新解锁、重新上锁 BL、刷分区或擦除数据。
先正常启动 Android，开启 USB 调试并在手机上授权 Mac：

```bash
adb devices -l
adb shell getprop ro.product.model
adb shell getprop ro.product.device
adb shell getprop ro.build.display.id
adb shell cat /proc/meminfo
```

核对确为目标设备后进入 bootloader fastboot（不要用 fastbootd）：

```bash
adb reboot bootloader
fastboot devices
fastboot getvar product
fastboot getvar unlocked
fastboot getvar is-userspace
```

上面 `adb reboot bootloader` 会重启设备。只连接这一台手机；项目主机脚本没有多设备选择功能。
可先运行 `python3 port/hackios-aston.py boot-uefi` 查看 UEFI 日志，之后同时长按电源键和音量上键返回 Android，
再重新进入 bootloader fastboot 执行完整体验。

## 完整体验

```bash
python3 port/hackios-aston.py boot-loader
python3 port/hackios-aston.py ramdisk
python3 port/hackios-aston.py run --secs 900
```

不要省略 `--secs 900`：脚本默认只有 30 秒，短于项目记录的约 3.5 分钟桌面启动时间。
system.apfs 约 2.5GB，每次重新启动 loader 都要重新上传，README 的实测上传时间约 91 秒。
run 命令会等待运行结束；内核运行中 USB fastboot 可能失联。
本机实测：单独长按电源未能退出；同时长按 **电源键 + 音量上键 15–20 秒** 可强制重启回 Android。
黑屏或振动后松开按键；若停在关机状态，再单按电源开机。
内核运行期间即便 macOS 仍显示 xnuloader USB 标识，fastboot reboot 也可能失败，不能保证能从电脑重启。
900 秒参数是请求运行时限，不能保证内核挂死后仍会按时退出。
不要使用关机后按双音量键插线的方式进入 fastboot：本机实测该组合进入 Qualcomm EDL 9008。
正常 Android 下使用上面的 adb reboot bootloader。
这不是恢复系统保证，异常情况需结合屏幕与日志判断。

预期可体验桌面和触摸，约 10fps；Wi-Fi、蓝牙、蜂窝、音频、Apple ID 当前不支持。

## 写入行为与日志

`fastboot boot` 本身是 RAM 启动，但整个项目不能称为完全不写分区：

- 本仓库 XnuLoader.c 的 FlushLog 会寻找 rawdump / logdump / oplusrawdump 并调用 WriteBlocks。
- 上游 xnuloader 的 write_logs 也会向日志分区写入。
- 因此默认构建保留了项目原有日志行为；未验证其对这台原厂系统的影响。

readlog 需要手机处于 xnuloader，若已回到 Android，要重新进入 bootloader 并启动 loader：

```bash
python3 port/hackios-aston.py readlog
```

由于重新启动 UEFI/loader 本身也可能写日志，不能保证旧日志完整保留。
不要添加 `ufs_write=1`，不要使用上游的分区安装流程。

参考：https://github.com/error-10/astonc-HakiOS （准备时 commit 87e76d5c63496f874905ed6c898ec3c3da2675aa）
