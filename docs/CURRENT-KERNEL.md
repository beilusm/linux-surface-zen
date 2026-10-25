# 当前默认配置：7.2.11-zen1 / 包修订 1

用户明确要求永远不要回退；“暂停／停止”只停止编译服务，“恢复／继续”
只利用现有输出和缓存续编。当前任务已按用户要求暂停，仍保留 7.2.11；
有空运行 `./scripts/background-build.sh start` 即可继续。

2026-10-25 查询 Zen 官方 release/tag 与 Arch 打包仓库，最新正式版为
[v7.2.11-zen1](https://github.com/zen-kernel/zen-kernel/releases/tag/v7.2.11-zen1)，
官方提交 `793e6d748c1cc142f66350d98eb492686d646192`，源码树
`44060ea3656948497f8c886712abe13218c0eae6`。7.2.12 目前只有 Liquorix 标签。
Arch 配置固定到 `6d5ef549cf31644d33b7c2951b5c3232f9332c51`，
linux-surface 固定到 `2294802a3f6eb8fc3cec502b5129b005c7c378db` 的
`patches/7.2/`（上游 BASE 为 v7.2.12，已逐个检查在 Zen 7.2.11 上应用）。
与旧移植的范围一致，仍排除 `0001-secureboot`、`0003-mwifiex` 和
`0011-surface-shutdown`；其余补丁合并为 `patches/surface-zen-7.2.11.patch`。

完整配置由新版 Arch、Surface 7.2 和日常片段重新合并生成，随后按原策略
裁剪 Pro 7。保留旧版 AF_ALG AEAD 排除项，默认模块选项仍为 5,616，完整
配置为 6,347；没有按当前已插设备删驱动。旧策略的全部排除项经新版
完整基线覆盖检查，默认配置相对旧版只有版本/工具探测与 vDSO memset
编译选项变化，驱动启用项相同。Rust 保持关闭，GCC/binutils 未变。

利用已缓存 7.2.9 归档和固定差异还原新版，计算出的全树 Git 哈希与官方
提交一致。重建归档 SHA-256 为
`9c40b7d12fca15ea4d949772f9cd91d602a89ca96895f16fae02cfd68964362f`，
这不是 GitHub tar.gz 的 SHA-256。独立重跑源码还原后，官方树哈希与归档
字节比较均一致。还原工具会校验固定的官方树哈希与归档
哈希，详见 [更新指南](UPDATING.md)。

通过 `work_profile=7.2.9-zen1` 沿用原绝对源码/输出路径，迁移前为旧源码
和约 25 GB 的 `build-daily` 建立 Btrfs reflink 快照，路径记录在
`work/7.2.9-zen1/.surface-zen-cache-snapshot`。源码按内容差异更新，未变
文件的时间戳和所有编译输出保留；`.cache/ccache/` 继续使用，默认容量
20 GB。旧内核安装包保留，系统当前运行的仍是 7.2.9。

已通过源码/补丁/归一化配置/release 检查、完整及裁剪配置的驱动覆盖检查、
脚本语法和 makepkg 元数据检查。后台增量编译已启动，早期 ccache 采样为
255 次命中 / 364 次可缓存编译（70.1%，不代表最终命中率或耗时）。
记录：`artifacts/reports/ccache-sample-7.2.11.json`。

新版构建/打包/归档验证交由 `scripts/background-build.sh` 连续执行，
实际状态以 `./scripts/background-build.sh status` 和日志为准。
此记录不表示新版编译、包验证或启动后的硬件测试已完成。

---

# 历史配置：7.2.9-zen1 / 包修订 5

2026-10-11 按用户要求改为 Surface Pro 7 + 日常外设配置，模块选项
6,347 → 5,616，减少 731 个选项（不是实际 `.ko` 文件数或时间百分比）。
保留 CH340/CH341、USB 外设、存储、文件系统、Intel/Surface 和容器功能；
移除的硬件范围、保护检查和回退方式见 [TRIMMING.md](TRIMMING.md)。

已验证归一化配置、源码/补丁/release，以及当前加载驱动没有落入裁剪路径。
完整配置和编译结果快照保留。`-5` 已完成编译、内核/headers 打包和包验证：
5,762 个预期模块齐全，CH341 等模块依赖、内核 BTF、headers 外部模块编译
及 `.BTF`/`.BTF.base` 检查通过。首次验证因解包根目录缺少 Arch 的
`/lib → /usr/lib` 链接失败，修复验证脚本后现有包通过全部检查。
报告：`artifacts/reports/package-check-7.2.9-zen1.buttR7/`。
`-5` 已安装并启动，用户报告重启测试成功。2026-10-11 读取本次启动日志：
系统/用户失败服务为 0、内核 tainted=0；IPTS/iptsd、i915、AX201、蓝牙、
USB 根盘与内置 NVMe 正常初始化，两次 s2idle 后 IPTS/iptsd 和 Wi-Fi 恢复。
Btrfs 设备错误计数均为 0。仍有固件温度阈值、USB U1、相机 probe 和睡眠切换
期间 iptsd/SAM 瞬时警告，未将其隐藏或据此修改系统。
详细记录见 `artifacts/reports/boot-5/review.md`。CH340 尚未接入实测，
其他外设、声音和长期睡眠稳定性仍需使用中确认。

---

# 历史配置：7.2.9-zen1 / 包修订 4

2026-10-10 检查 Zen GitHub release API 与 tag 列表，最新版本仍为
[v7.2.9-zen1](https://github.com/zen-kernel/zen-kernel/releases/tag/v7.2.9-zen1)。
linux-surface master 仍为 `bf1921fc63f33d03a007fb38c4f88ff7e7bc1a55`，
Arch 参考配置为 `acb62356eb8c55d46a000e3a02f5614814da70b8`。
源码归档 SHA-256 与已有移植补丁不变。

本次用固定 Arch Zen 参考配置，叠加 Surface 6.19 配置片段和
`configs/fragments/daily.config`，运行 `olddefconfig` 后保存为
`configs/7.2.9-zen1/surface-daily.config`。6,343 个原 Arch 模块选项中，
`PINCTRL_ICELAKE` 改为内置，`CRYPTO_USER_API_AEAD` 按 Surface 配置关闭；
其余全部保留。增加 Surface 驱动后有 6,347 个模块选项（实际 `.ko`
文件数由 Kbuild 决定，不等于 Kconfig 模块选项数）。

CH340 使用内核内置提供的 `drivers/usb/serial/ch341`，表中包含
`1a86:7523`、`1a86:5523` 等 USB ID。不使用运行时设备列表裁剪，
以后没插过的串口、网卡、UVC 摄像头和 USB 声卡也能自动加载驱动。
配置检查会逐项核对参考 Arch 的全部模块选项，发现裁剪立即失败。

性能取舍仅限构建流程：全部逻辑 CPU 并发（本机 8，JOBS 可覆盖）、可选 ccache、增量输出、
不构建 HTML 文档、GCC 无 LTO、降低 zstd 压缩级别。DWARF5 和 BTF
保留；Rust 关闭、Binder 使用 C 实现、panic 画面使用 user。旧 `-3`
编译输出未覆盖，新输出位于 `work/7.2.9-zen1/build-daily/`。

当前验证状态以 `artifacts/reports/` 和构建日志为准；完整配置的
启动、实际外设与睡眠测试需要新包安装重启后完成。下面旧记录仅适用
原 `-1`/`-2`/`-3` 精简包，不能作为 `-4` 硬件验证证据。

---

# 历史记录：Surface Pro 7 精简配置（包修订 1–3）

这是为本机（Surface Pro 7 / i5-1035G4 / Arch Linux）制作的独立内核：
`7.2.9-zen1-surface-zen`。它不会覆盖现有的 `linux-surface` 或
`linux-zen`。Zen 基线固定为 2026-10-03 发布的 `v7.2.9-zen1`；
Surface 改动来自 linux-surface 的 6.19 补丁目录，基准提交
`bf1921fc63f33d03a007fb38c4f88ff7e7bc1a55`，并针对 Zen 7.2.9
移植于 `patches/surface-zen-7.2.9.patch`。Arch Zen 配置来自
`acb62356eb8c55d46a000e3a02f5614814da70b8`。

该补丁包括 IPTS（触摸/笔的内核侧）、ITHC、Surface Aggregator、
Type Cover、按键、相机 IPU3/传感器/隐私灯等。实际设备上的触摸 MEI
控制器是 `8086:34e4`，IPU 是 `8086:8a19`，无线网卡是 Intel
`8086:34f0`。Surface 补丁中的 `0001`（撤销 EFI NX，且本机 Secure
Boot 已关闭）、`0003`（Marvell WiFi）、`0011`（只匹配较新型号的
关机 PCI 特例）没有纳入；`0015` 涉及的 TAD RTC 功能已被 7.2
代码重构；`0017–0024` 是旧版的网络安全修复，没有从旧内核原样
重复应用。不可将此移植补丁视为适用于其他 Surface 型号的完整补丁集。

`configs/7.2.9-zen1/surface-pro7.config` 由 Arch Zen 配置、Surface 片段和本机
`localmodconfig` 生成，并额外保留相机、键盘盖、USB 存储、ext4、XFS、
exFAT 等驱动。Ice Lake GPIO 控制器以 `CONFIG_PINCTRL_ICELAKE=y`
内置，同时保留 `CONFIG_GPIO_TPS68470=m` 相机 PMIC GPIO 驱动，避免
`localmodconfig` 裁掉相机供电/复位所需的 GPIO 支持；构建脚本会检查
这两个选项。它把模块数从约 6,343 个降至约 285 个，针对这台
Pro 7，不能视为通用发行版配置。Rust 支持（本机缺少 `rust-bindgen`/
`rust-src`）仍关闭；panic 画面设为普通 `user` 模式，避免缺少 Rust
二维码支持时产生警告。恢复 DWARF5 和内核/模块 BTF，以支持 systemd
的 `RestrictFileSystems=`；headers 包保留 BTF 及 `resolve_btfids` 工具，
打包时移除 `vmlinux` 中体积较大的 DWARF 段。IPTS 和 Surface Aggregator 以模块
形式编译。首次尝试的全量编译输出留在 `work/archive/build-full/`，可供以后研究。

在本目录运行：

```bash
JOBS=4 ./build.sh
./scripts/package.sh -f
```

默认使用 `JOBS=4`；若内存压力大可改为 `JOBS=3`。
第一条命令验证下载包 SHA-256，按需提取固定的 Zen tag、应用
已移植补丁、使用预生成的 Pro 7 配置并编译。
第二条命令生成 `linux-surface-zen` 和 `linux-surface-zen-headers`
的 Arch 安装包；它会复用已编译的输出。

仅在检查软件包之后，如要在本机安装：

```bash
sudo pacman -S --needed wireless-regdb
sudo pacman -U ./artifacts/packages/linux-surface-zen-7.2.9.zen1-3-x86_64.pkg.tar.zst \
  ./artifacts/packages/linux-surface-zen-headers-7.2.9.zen1-3-x86_64.pkg.tar.zst
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

`wireless-regdb` 会由 pacman 自动带入所需的 `iw`。若自行从源码打包，
请先安装 `wireless-regdb`，再运行 `./scripts/package.sh -f`。

先在 GRUB 菜单选择新内核；保留原有 `linux-surface` 内核作为回退。
`iptsd` 仍是触摸/手写笔的数据处理所需的用户空间组件，内核模块
单独安装不等于触摸已可用。相机是否能在所用 libcamera/应用中工作
取决于对应 ISP 的支持：本机 `8086:8a19` 是 IPU4，linux-surface 的
[相机支持表](https://github.com/linux-surface/linux-surface/wiki/Camera-Support)
目前将 Pro 7 的前置、后置和 IR 相机列为不支持。本配置保留的 IPU3
及传感器模块不能驱动本机 IPU4；安装 libcamera 本身也不能补齐内核
驱动。不要仅凭编译通过就认为休眠、相机、触摸已经验证。

`-2` 版已在本机启动，用户确认多次睡眠唤醒后触摸和触控板正常；
`-3` 版修复 BTF/panic 画面配置，并将 `wireless-regdb` 设为依赖以补齐
`regulatory.db`。`-3` 已在本机启动，BTF、无线数据库和 panic 画面配置警告已消失；
睡眠/触摸在 `-3` 上仍需重复确认。
`-3` 版编译及内核指令测试已通过；安装包中的内核/模块 BTF、285 个
模块及属主/权限已检查。解包后的 headers 也已成功编译一个带
`.BTF` 和 `.BTF.base` 的临时外部模块（未加载）。

来源校验：

```text
Zen v7.2.9-zen1 tar.gz SHA-256:
814d32e75ca07fcc0bd8290ade366ea66c3ca0c33242995b41b29e3dd9d18bb5
```

今后 Zen 更新时应重新检查 linux-surface 移植补丁及编译结果。当前
默认清单固定在 7.2.9；更新流程见 [UPDATING.md](UPDATING.md)。
