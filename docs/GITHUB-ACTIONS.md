# GitHub Actions 编译

仓库：<https://github.com/beilusm/linux-surface-zen>。
工作流仅手动触发：Actions → **Build Surface Zen** → **Run workflow**。
默认构建当前清单的 Pro 7 日常配置，使用 Ubuntu runner 上的 Arch 容器，
按 `ci/build.env` 固定 Arch 仓库日期，安装原生 GCC/Arch 打包依赖。
容器中的项目路径与本机一致，因此本地 `.cmd`、调试信息路径和 ccache
有机会直接复用；工具链/依赖内容变化时仍由 Kbuild 和 ccache 正确重编。

## 首次迁移本机进度

```bash
./scripts/background-build.sh stop
./scripts/ci-export-cache.sh
cat artifacts/ci-transfer/latest
```

导出锁定当前源码和输出，包含项目 ccache、已校验的新源码归档、工作源码
和当前配置的编译输出。按 1,800 MiB 分块，附清单与 SHA-256，不包含
模块签名私钥、Git 认证数据、旧版本存档或电脑上的其他目录。
云端会生成新的临时模块签名密钥，相关证书/目标会正常重新生成和链接。
导出不会清理、回退或覆盖本地缓存和输出。

将分块、`manifest.json`、`SHA256SUMS` 上传到专用 GitHub prerelease，
首次运行将该 release 的 tag 填入 `bootstrap_tag`。传输数据是本项目
的编译中间产物，在公开仓库中可以被下载。

已有 seed release 后也可使用上传助手；已完成的同名分块会跳过，全部
上传后自动触发正式构建。放在 systemd 用户服务中可独立于终端持续上传：

```bash
systemd-run --user --unit=surface-zen-cloud-transfer \
  --working-directory="$PWD" \
  /usr/bin/python "$PWD/scripts/ci-upload-cache.py" \
  --repo beilusm/linux-surface-zen --tag <seed-tag> \
  --directory "$(cat artifacts/ci-transfer/latest)"
journalctl --user -u surface-zen-cloud-transfer -f
```

上传状态也写在导出目录的 `cloud-transfer.json` 中。首次迁移实测
13,940,091,945 字节（12.98 GiB），8 个分块；这不是 Git 历史大小。

## 云端续编与下载

工作流优先恢复同一输入的最新增量检查点；没有检查点时才导入本机进度。
检查点保存源码时间戳和完整增量输出，避免为了普通续编重复下载本机
ccache。ccache 首次迁移时导入；后续同配置主要直接复用 `.o`，新机器
上从编译输出继续推进。云端不会更改本地工作树或内核版本。

默认每轮最多编译 240 分钟，然后为打包检查点/上传留下余量；可选
`build_minutes` 范围 1–270。软超时会显示失败，但随后仍保存检查点；
再次运行工作流即可增量继续。GitHub 标准托管 job 的硬时限是 6 小时，
手动 **Cancel workflow** 或硬超时可能使本轮来不及上传，只能从上一轮
已保存的云端检查点继续。为保留进度，优先让设定的编译时间片自然结束。

完整输出经 zstd 压缩后使用 Actions cache 保存，key 包含版本、配置和
构建输入，并按运行编号更新。默认免费缓存总额为 10 GB，旧检查点会按
GitHub 的规则淘汰；不自动提高额度或启用付费 runner。若检查点本身
超过额度，保存可能失败，应查看保存步骤；本机原输出和初次导入 release
仍保留。runner 会释放自身预装 SDK 空间并检查至少 50 GiB 可用磁盘。

编译后自动生成内核/headers 两个 Arch 包，并运行完整模块、BTF 和
外部模块 headers 检查。验证成功后在仓库 **Releases** 中下载该次运行的
两个 `.pkg.tar.zst`；日志和报告另存为该 release 的 `diagnostics.tar.gz`。
未通过检查时仅发布诊断包。结果链接也显示在运行摘要中，不使用 Actions
artifact 存储，不因反复构建累积占用账号的 artifact 免费额度。

```bash
gh workflow run kernel.yml -R beilusm/linux-surface-zen -f flavor=pro7
gh run list -R beilusm/linux-surface-zen
gh release list -R beilusm/linux-surface-zen
gh release download <结果tag> -R beilusm/linux-surface-zen -p '*.pkg.tar.zst'
```

公开仓库标准 Linux runner 当前为 4 vCPU / 16 GB RAM。迁移的直接收益是
电脑不再承担编译负载；实际速度取决于云端 CPU、缓存和上传带宽，不保证
固定倍数提速。工作流不会安装内核或修改电脑的启动项。

参考：[runner 规格](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、
[运行时限](https://docs.github.com/en/actions/reference/limits)、
[缓存限制](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)。
