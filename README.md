# Surface Pro 7: Zen 7.2.9 + linux-surface

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

Arch Zen 配置和 Surface 配置片段合并后关闭了 Rust 支持（本机缺少
`rust-bindgen`/`rust-src`）及调试符号（本机只有 8 GB RAM）；其余尽量
保持 Arch Zen 配置。IPTS 和 Surface Aggregator 以模块形式编译。

在本目录运行：

```bash
JOBS=3 ./build.sh
makepkg -f
```

`JOBS=3` 适合这台 8 GB 内存的机器。第一条命令验证下载包 SHA-256，
按需提取固定的 Zen tag、应用已移植补丁、生成配置并编译。
第二条命令生成 `linux-surface-zen` 和 `linux-surface-zen-headers`
的 Arch 安装包；它会复用已编译的输出。

仅在检查软件包之后，如要在本机安装：

```bash
sudo pacman -U ./linux-surface-zen-7.2.9.zen1-1-x86_64.pkg.tar.zst \
  ./linux-surface-zen-headers-7.2.9.zen1-1-x86_64.pkg.tar.zst
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

先在 GRUB 菜单选择新内核；保留原有 `linux-surface` 内核作为回退。
`iptsd` 仍是触摸/手写笔的数据处理所需的用户空间组件，内核模块
单独安装不等于触摸已可用。相机是否能在所用 libcamera/应用中工作
还需要开机实测。不要仅凭编译通过就认为休眠、相机、触摸已经验证。

来源校验：

```text
Zen v7.2.9-zen1 tar.gz SHA-256:
814d32e75ca07fcc0bd8290ade366ea66c3ca0c33242995b41b29e3dd9d18bb5
```

今后 Zen 更新时应重新检查 linux-surface 移植补丁及编译结果；这个
目录固定在 7.2.9，不会悄悄把 6.19 补丁套到下一个新版本。
