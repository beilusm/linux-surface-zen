# 更新内核

项目固定使用已审查的版本，不自动追随最新 tag。版本清单位于
`versions/`，`project.conf` 选择默认版本；构建和打包都读取同一份清单。

## 预检候选版本

将下例中的版本替换为实际存在的 Zen tag（此处只是命令格式）：

```bash
./scripts/check-update.sh 7.2.10-zen1
```

若已有可信的归档 SHA-256，可作为第二个参数传入。未提供时脚本会
记录下载文件的校验值，但这不等于用独立来源验证了文件真实性。
脚本在 `work/preflight/` 中提取新源码，检查当前 Surface 补丁是否
能完整应用，运行 `olddefconfig`，比较配置并检查关键选项与 release。
结果写到 `artifacts/reports/`。不编译内核、不改默认版本、不安装。

补丁无法应用时必须移植，不能用忽略失败、强行套补丁或只改版本号
的方式跳过。跨内核版本时也要审查上游 linux-surface 补丁：能应用
不代表语义正确或没有漏掉新修复。保留原始来源提交和移植说明。

## 建立新版本

预检通过后，获取对应版本的完整 Arch Zen 配置到
`configs/reference/arch-zen-<内核版本>.config`，记录对应来源提交。
不得继承旧 `localmodconfig` 精简结果作为新版默认配置。用新 Arch 配置、
对应 Surface 片段及 `configs/fragments/daily.config` 合并后归一化完整基线：

```bash
bash <新源码>/scripts/kconfig/merge_config.sh -m -O <临时输出目录> \
  configs/reference/arch-zen-<内核版本>.config \
  configs/reference/surface-<补丁版本>.config configs/fragments/daily.config
make -C <新源码> O=<临时输出绝对路径> LOCALVERSION= olddefconfig
```

完整配置更新 `arch_config_file`，核对
参考配置的全部模块仍可用；跨版本出现改名/删除时逐项审查，而非删除
覆盖检查。预检使用当前 Arch 参考检查，只是兼容性初筛，不能代替新
版本参考配置的复核。

审查报告中的 `config.diff`。将归一化配置保存到
`configs/<新版本>/surface-daily.config`，移植补丁保存为独立文件，
然后按 [裁剪指南](TRIMMING.md) 重新生成/审查 Pro 7 策略、片段和归一化
`surface-pro7-daily.config`。默认清单配置路径应指向该日常裁剪配置，
`config_policy_file` 指向该版本审查后的策略，`build_subdir=build-daily`。
旧版策略只供参考，不自动把新版驱动变化加入豁免表。

复制报告中的 `candidate.conf` 为 `versions/<新版本>.conf`，核对其中
的路径、SHA-256、来源提交及包版本。同一内核的打包修复递增
`package_release`；新内核从 `1` 开始。不要覆盖旧版清单与补丁。

不改默认值也能构建候选版本：

```bash
SURFACE_ZEN_PROFILE=7.2.10-zen1 ./build.sh --check
SURFACE_ZEN_PROFILE=7.2.10-zen1 JOBS=4 ./build.sh
SURFACE_ZEN_PROFILE=7.2.10-zen1 ./scripts/package.sh
```

构建目录默认是 `work/<版本>/`。需要复用大量既有编译输出时，可以在
新版本清单显式设置 `work_profile=<旧版本>`，保留 Kbuild 命令中的原绝对路径。
先完成新版配置和补丁预检，再执行（这里的版本是已实际核验的升级）：

```bash
SURFACE_ZEN_PROFILE=7.2.11-zen1 ./scripts/reuse-build.sh 7.2.9-zen1
SURFACE_ZEN_PROFILE=7.2.11-zen1 ./build.sh --check
SURFACE_ZEN_PROFILE=7.2.11-zen1 ./scripts/background-build.sh start
```

迁移脚本与打包/编译共用文件锁，要求基线源码身份正确且有已完成输出。
先用 `cp --reflink=always` 将旧源码和当前 flavor 的输出独立快照到
`work/archive/`，不使用硬链接，也不会在不支持 reflink 时自动复制几十 GB。
再校验并应用新版补丁，按内容比较更新原源码目录：未变文件保留时间戳，
变化文件使用新时间戳，已有 `.o`、`.cmd`、ccache 和旧安装包全部保留。
Kbuild 仍负责判断受影响的目标；不改写 `.cmd` 或伪造已完成构建标记。
共享工作目录同一时刻只对应一个源码身份，旧版本构建会拒绝使用新版源码。
旧版安装包可用于回退；若需恢复工作树，先停止构建并持有同样的锁，
将 `.surface-zen-cache-snapshot` 指向的 `kernel` 和输出目录恢复到原路径。
中断的源码迁移也应先从该快照恢复，不能手工补写身份标记。

7.2.11 的 GitHub 完整归档下载被限流，因此使用本地已校验的 7.2.9
归档和 `patches/upstream/zen-7.2.9-to-7.2.11.patch` 还原源码。
新版清单同时固定旧归档 SHA-256、差异文件 SHA-256、官方提交的 Git tree、
归档时间和重建归档 SHA-256。`scripts/reconstruct-source.sh` 在全树哈希
匹配后才生成归档；该 SHA-256 **不是 GitHub 自动生成 tar.gz 的校验值**。
缓存中已有归档时直接使用，不重复还原或下载。

清单对应的源码 SHA-256 或移植补丁发生变化时，构建脚本仍会拒绝复用该源码树。
把该版本的工作目录改名留存后重新构建，或建立新的 Zen tag 清单；
不要修改身份标记绕过检查。修改配置或工具链后会重新进入编译过程。

## 验证、安装与切换默认版本

构建成功后运行 `./scripts/check-package.sh`，检查实际包中的全部
模块、别名/依赖、BTF，并用 headers 编译带 BTF 的外部模块。该检查
不安装包、不加载模块。保留旧内核，手动用
pacman 安装 `artifacts/packages/` 中选定的两个包并更新 GRUB。
用户安装系统包，项目脚本不自动调用 pacman。

新内核启动后核对 `uname -r`、服务状态和内核日志，测试触摸、笔、
键盘盖、Wi-Fi、声音和多次睡眠唤醒。跨版本保留必要的硬件配置，
不要重新运行无保护的 `localmodconfig` 裁掉未加载的设备驱动。
Pro 7 的 IPU4 摄像头限制不因补丁预检通过而解决。

通常在配置/编译和包检查通过后修改 `project.conf` 的 `default_profile`。
用户要求直接升级项目并在后台编译时，可先指定已预检的版本，并在当前记录
中注明后台构建尚未结束、包检查和硬件验证待完成。该文件只影响
本项目默认构建版本；GRUB 的启动选择仍由系统配置控制。
