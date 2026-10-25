# Surface 的 Arch Zen 内核

默认基线为 `7.2.11-zen1`，安装包修订为 `1`，内核 release 为
`7.2.11-zen1-surface-zen`。2026-10-25 核查 GitHub releases/tags，最新
Zen 正式版为 [v7.2.11-zen1](https://github.com/zen-kernel/zen-kernel/releases/tag/v7.2.11-zen1)；
7.2.12 当前只有 Liquorix 标签。编译和包验证状态以后台任务结果为准，
新版尚未安装或进行启动后的硬件验证。

默认使用 **Surface Pro 7 + 日常外设配置**。完整 Arch Zen/Surface 配置
保留在 `surface-daily.config`；针对 Intel Ice Lake 的裁剪策略见
[裁剪说明](docs/TRIMMING.md)。模块选项从 6,347 降到 5,616；不使用
`localmodconfig`，不按当前已插入设备删除驱动。

包格式和路径遵循 Arch 内核约定：pacman 安装时通过系统的
kmod/mkinitcpio hooks 更新模块索引、内核与 initramfs，headers
可供 DKMS/外部模块使用。

## 日常功能

- USB 串口：CH340/CH341（`ch341`）、CP210x、FTDI、PL2303、CDC ACM 等。
- USB 存储/UAS、NVMe、SATA/AHCI、SD 读卡器、磁盘加密、设备映射和软件 RAID。
- USB 打印机、UVC/GSPCA 摄像头、USB 声卡、蓝牙、键鼠和手柄。
- USB 网卡、Wi-Fi、手机 USB 网络共享、VPN、防火墙和容器网络。
- ext4、Btrfs、XFS、FAT/exFAT、NTFS3、FUSE、OverlayFS、SMB/CIFS、NFS。
- Intel KVM、VirtIO、VirtualBox 来宾模块、WireGuard、NTSYNC、BPF/systemd 安全功能。
- Intel i915/AX201/音频/温控及 Surface IPTS/ITHC、SAM、键盘盖、电池和传感器。

裁掉 AMD/NVIDIA/Xe 等非本机 GPU、AMD 专用平台驱动、其他厂商笔记本
平台驱动、服务器 RDMA/专用网卡/计算与加密加速卡，以及用户明确不需要的
数字电视棒、SDR、PCIe 采集卡和专业 PCIe 声卡。保留部分模拟采集基础支持，
因为 STK1160、GO7007 等 USB 采集设备也依赖它。

Rust 因缺少 `rust-src`/`rust-bindgen` 关闭，Android Binder 使用 C 实现；
保留 DWARF5、内核/模块 BTF 和 headers 的 BTF 工具。通用 CPU/安全代码中
仍可能出现 AMD 名字；不按名字盲删共享代码。

CH340 无需下载厂商驱动，启动新内核后由 udev 根据 USB ID 自动加载
`ch341`，产生 `/dev/ttyUSB*`。串口访问权限仍由系统的 udev/用户权限
配置决定。设备固件使用 `linux-firmware`，触摸/笔使用 `iptsd`；
Pro 7 的 IPU4 相机限制不因恢复通用 UVC/IPU3 驱动而解决。

## 后台构建（无需反复检查）

也可将编译负载转到 [GitHub Actions](docs/GITHUB-ACTIONS.md)：支持首次导入
本机缓存/进度、云端检查点续编，以及下载验证后的内核和 headers 安装包。

```bash
./scripts/background-build.sh start    # 脱离终端，自动编译、打包、验证
./scripts/background-build.sh stop     # 电脑卡顿时暂停，保留版本、进度和缓存
./scripts/background-build.sh start    # 有空再运行，同一版本增量继续
./scripts/background-build.sh status   # 需要时查看一次状态
./scripts/background-build.sh log      # 人工实时看日志，Ctrl-C 只停止查看
```

本项目中“恢复”始终指增量续编，不回退内核版本或恢复旧快照。暂停后
不会自动重启编译，需要继续时再运行 `start`；仅中断时尚未完成的目标
可能需要重做，已完成的输出和 ccache 会继续使用。

任务由 systemd 用户服务托管，独立于启动命令的终端/工具会话；
需要本机的 systemd 用户管理器运行。状态写入 `artifacts/background/`，
成功为 `success`，失败为 `failed`
并保留日志。后台任务结束后自动运行包检查，不需要 Codex 持续轮询。
`status` 同时显示 systemd 服务状态，能识别未启动或意外退出的任务，
避免停留在 `queued`/`running`；服务日志也可通过 `journalctl --user -u <服务名>` 查看。
`adopt` 可等待已经开始的打包任务，再自动验证产物；等待通过文件锁
完成，没有定时查询。前台/后台均保留增量输出，失败后可再次 `start`。

## 构建和验证

```bash
./build.sh --check              # 源码、补丁、配置及日常功能/裁剪策略检查
./scripts/package.sh -f         # 增量编译，再生成内核和 headers 两个包
./scripts/check-package.sh      # 检查实际包、模块依赖、BTF，并编译外部模块
```

默认使用 `nproc` 返回的全部可用逻辑 CPU，本机默认 `JOBS=8`。
可用 `JOBS=3 ./scripts/package.sh -f` 给桌面留更多余量；环境变量 `JOBS`
优先，不会继承 `/etc/makepkg.conf` 的 `-j8` 而失控。

安装 ccache 后自动启用，缓存位于 `.cache/ccache/`，默认最多 20 GB；
`USE_CCACHE=0` 可关闭，`CCACHE_MAXSIZE=10G` 可限制容量。增量输出保留
在 `work/7.2.9-zen1/build-daily/`，完成产物复用前会检查所有预期模块。
新版通过清单的 `work_profile=7.2.9-zen1` 保留原绝对路径，避免 `.cmd`
记录中的路径变化触发重编。升级前的源码/默认输出写时复制快照位于
`work/archive/`，具体路径记在 `work/7.2.9-zen1/.surface-zen-cache-snapshot`。
完整配置的旧编译输出保留在 `work/7.2.9-zen1/build-full/`。配置变更可能重编受影响文件，不能保证全部
对象均复用；重复打包和同配置中断恢复可复用输出/编译缓存。

不编译 HTML 文档，不使用 LTO；模块使用 zstd 3，安装包使用 zstd 6/
4 线程，避免本机默认的 zstd 20/全部线程带来的长时间压缩和内存压力。
压缩和 LTO 设置不影响驱动覆盖。headers 保留 BTF，去除体积较大的 DWARF 段。

工具依赖在 `PKGBUILD` 中，ccache 为可选工具。两个包位于
`artifacts/packages/`，日志位于 `artifacts/logs/`。项目脚本不调用 sudo、
安装系统包或修改 GRUB。

## 安装

完成打包与检查后执行：

```bash
sudo pacman -U ./artifacts/packages/linux-surface-zen-7.2.11.zen1-1-x86_64.pkg.tar.zst \
  ./artifacts/packages/linux-surface-zen-headers-7.2.11.zen1-1-x86_64.pkg.tar.zst
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

pacman 会处理声明的依赖；`linux-firmware` 和 `iptsd` 是可选依赖，
本机已安装。保留 `linux-zen`/`linux-surface` 回退内核。重启后测试
USB 串口、触摸/笔、键盘盖、Wi-Fi、声音和睡眠唤醒；包修订不出现在
`uname -r` 中，应以 `pacman -Q linux-surface-zen` 区分包修订。

## 项目输入与更新

```text
project.conf                 默认版本
versions/                    版本、SHA-256、包修订及输入路径
configs/<版本>/surface-pro7-daily.config  默认归一化配置
configs/<版本>/surface-daily.config       留存完整配置
configs/policies/                        可审查的裁剪策略
configs/reference/           固定来源的 Arch / Surface 参考配置
configs/fragments/daily.config       最小本地覆盖
patches/                     经移植的 Surface 补丁
scripts/                     构建、打包、配置检查、包检查和更新预检
work/<版本>/kernel           源码
work/<版本>/build-daily      默认增量编译输出
work/<版本>/build-full       完整配置编译快照
.cache/                      源码下载、ccache 和上游参考仓库
artifacts/                   安装包、日志和验证报告
```

根目录 `kernel` 链接指向沿用的工作源码树；根目录 `build` 链接及
`work/7.2.9-zen1/build/` 仍供原来的 `-3` 编译输出留存。新脚本直接使用
版本清单里的路径，不使用旧 `build`。工作目录名不再代表其中的内核版本，
以源码身份检查和 `make kernelrelease` 为准。旧版源码身份与当前工作树
不符时会拒绝构建，回退可用已保留的旧安装包或升级前快照。
输入配置和工具链变化会让完成产物缓存失效，不会把旧精简包冒充新版。

[当前配置与验证记录](docs/CURRENT-KERNEL.md) ·
[更新指南](docs/UPDATING.md)
