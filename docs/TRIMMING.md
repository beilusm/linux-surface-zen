# Surface Pro 7 日常配置裁剪

默认包修订为 `5`，配置为 `configs/7.2.9-zen1/surface-pro7-daily.config`。
来源是完整 Arch Zen + Surface 配置，并按 `configs/policies/surface-pro7.json`
的 Kconfig 定义路径/明确选项裁剪，不运行 localmodconfig。
明确裁剪项及归一化后的依赖移除项都已记录；构建检查拒绝未审查的额外删除。

## 保留与移除

当前机器是 Surface Pro 7 / Intel i5-1035G4、i915、AX201、Intel HDA/SOF。
根目录当前在 USB 硬盘的 Btrfs 上，因此 USB_STORAGE、UAS、SCSI、BLK_DEV_SD、
Btrfs、xHCI 及 EFI/分区支持均保留。内置 NVMe、SATA/AHCI、SD/MMC、
USB 桥接盒、设备映射/LUKS、软件 RAID、常见文件系统也保留。

USB 串口（包括 CH340/CH341）、所有原配置启用的 USB 网络/无线驱动、
蓝牙、HID、USB 音频、UVC/GSPCA 摄像头、USB 采集、打印机和手柄继续保留。
保留容器、VPN、防火墙、Intel KVM、VirtIO、VirtualBox、NTSYNC、BPF/BTF。

移除非本机 GPU，包括 AMD Radeon/AMDGPU、NVIDIA Nouveau/Nova、较新 Intel Xe
和其他 SoC GPU；保留 i915、USB 显示及虚拟显卡。移除 AMD 专用平台、其他
笔记本厂商/工业板平台驱动、服务器 RDMA/NTB/专用网络/计算和加密加速卡。
用户明确同意移除数字电视棒、SDR、PCIe 采集卡和专业 PCIe 声卡，FireWire
也移除。普通 USB 音频及 HDA/Intel SOF 不受影响。

部分 USB 模拟采集设备被 Kconfig 分类为模拟电视，所以保留模拟采集基础
支持；AU0828 需要 DVB 核心，随数字电视支持移除。未来买非通用 USB 采集器
或特殊外设时应核对芯片支持，不能承诺任意外设均适配。

AMD 的通用 CPU 检测、安全缓解、共享 PHY/quirk 代码可能仍出现 AMD 名字。
它们通常体积很小或服务共享基础设施，不以字符串匹配批量删除。

模块选项 6,347 → 5,616，少 731 个。大 GPU 的源码量远高于普通小模块，
选项数减少比例不等于编译时间减少比例。保留 DWARF/BTF 与完整 headers。

## 续编、回退与更新

原完整输出已用 Btrfs reflink 快照到 `work/7.2.9-zen1/build-full/`，默认
仍在原 `build-daily/` 路径续编，以减少因移动输出路径重编构建工具的开销。
没有删除 ccache，也没有 make clean。配置变化仍会重编受影响的文件。

恢复默认编译（8 线程、后台自动打包验证）：

```bash
JOBS=8 ./scripts/background-build.sh start
```

需要回到完整配置时先停止当前后台任务，然后：

```bash
SURFACE_ZEN_FLAVOR=full JOBS=8 ./scripts/background-build.sh start
```

完整配置仍生成原 `-4` 包；默认裁剪配置生成 `-5` 包。二者 pkgbase/release
相同，安装时相互替换，不能作为同时安装的两个独立内核。

升级版本应重新取新 Arch/Surface 基线，用 `scripts/trim-config.py` 与新
Kconfig 生成裁剪片段，合并后 olddefconfig，逐项审查新增/消失选项和依赖。
不要直接复制旧版的 `reviewed_exclusions` 作为新版豁免表。

```bash
python scripts/trim-config.py <源码> <完整配置> <策略JSON> <输出片段> <明确移除JSON>
bash <源码>/scripts/kconfig/merge_config.sh -m -O <临时输出目录> <完整配置> <输出片段>
make -C <源码> O=<临时输出绝对路径> LOCALVERSION= olddefconfig
```

`reviewed_exclusions` 是人工审查后的依赖移除表，`required_disabled` 是明确
裁剪项；`baseline_config` 必须指向对应版本的完整归一化基线。
配置检查、完整构建、包验证和实际启动/外设/睡眠测试依次完成。
