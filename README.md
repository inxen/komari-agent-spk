# Komari Agent for Synology DSM

将 [Komari Agent](https://github.com/komari-monitor/komari-agent) 打包为 Synology DSM 7.x Package Center 可安装的 `.spk` 套件。

Komari Agent 是一款轻量级服务器监控客户端，可将 NAS 的系统运行状态上报至 Komari 监控服务端。本套件直接打包上游官方 Release 二进制（不修改核心代码），以**专用套件用户（非 root）**运行，纯 bash + CGI 实现，无第三方运行时依赖。

## 特性

- **非 root 运行**：`run-as: package` 专用套件用户，符合 DSM 7 强制降权要求，不影响 `/proc`、`/sys` 等监控数据读取
- **配置窗口**：Package Center「打开」弹出 DSM 原生窗口，内嵌 JSON 编辑器直接编辑 `config.json`
  - 保存时 JSON 语法校验，原子写入（临时文件 → 校验 → 替换），失败不损坏原配置
  - 「保存配置」仅保存；「应用配置」保存并重启 Agent
  - 认证基于 DSM 登录会话 cookie，token 不进入 URL / 日志 / 命令行
- **安装静默、卸载可选**：安装 / 升级 / 覆盖安装均不弹向导；卸载时弹出「保留配置 / 完全卸载」单选
- **配置持久化**：`config.json` 存放于数据目录（`@appdata`），升级与卸载后重装均可保留
- **日志管理**：自动轮转（10 MiB × 3 份，上限约 40 MiB），随服务启停的后台守护保证长期运行不会无限增长
- **三架构云构建**：GitHub Actions 一键产出 x86_64 / armv8 / armv7 安装包，版本跟随 komari-agent

## 安装

1. 从 [Releases](https://github.com/inxen/komari-agent-spk/releases) 下载对应架构的 `.spk`（x86_64 / armv8 / armv7）
2. DSM → 套件中心 → 手动安装 → 选择 `.spk` 文件（需先在「设置 → 信任层级」允许第三方未签名套件）
3. 安装全程静默，完成后 Agent 自动启动
4. 在套件中心「打开」Komari Agent，在配置窗口中填入 `endpoint` 与 `token` 并应用

> 国内网络访问 GitHub 不稳定时，可手动下载 [komari-agent](https://github.com/komari-monitor/komari-agent/releases) 二进制后本地构建（见下文）。

## 支持范围

| 项 | 说明 |
| --- | --- |
| DSM 版本 | 7.x（`os_min_ver="7.0-40000"`） |
| 架构 | `x86_64`、`armv8`（ARM 64 位）、`armv7`（ARM 32 位），按官方 platform family 打包，同一架构族共用同一 SPK |

## 配置说明

配置文件：`/var/packages/KomariAgent/var/config.json`（数据目录 `@appdata`，升级保留；卸载时按选择保留或清除）。

字段与 komari-agent 官方配置一致。常用字段：

```json
{
  "endpoint": "https://monitor.example.com",
  "token": "your-agent-token",
  "interval": 3,
  "disable_auto_update": true,
  "protocol_version": 2
}
```

| 字段 | 说明 |
| --- | --- |
| `endpoint` | 面板地址 |
| `token` | agent token |
| `interval` | 数据采集间隔（秒），默认 3 |
| `disable_auto_update` | 禁用 Agent 自身自动更新（默认 `true`） |
| `disable_web_ssh` | 禁用远程控制（web ssh / rce） |
| `ignore_unsafe_cert` | 忽略不安全证书 |
| `protocol_version` | 上报协议版本（默认 2） |
| `disable_compression` | 禁用 v2 压缩 |
| `prefer_ip_version` | 4 或 6 |

完整字段以当前上游版本为准（`komari-agent --help` 或上游 [readme.md](https://github.com/komari-monitor/komari-agent/blob/main/readme.md)）。

> `disable_auto_update` 默认设为 `true`（即禁用了 Agent 自身自动更新），避免 komari-agent 自更新就地覆盖套件内二进制导致版本不一致；升级请通过套件升级完成。

## 日志

- Agent 日志：`/var/packages/KomariAgent/var/log/komari-agent.log`（轮转后含 `.1/.2/.3`）
- 正常连接面板时日志量极小（仅启动信息）；面板失联时约 7 MB/天
- **自动轮转**：单文件超过 10 MiB 轮转并保留 3 份备份，磁盘占用上限约 **40 MiB**

## 卸载

卸载时套件中心会弹出选项：

- **仅卸载（保留配置）**：保留 `config.json`、日志和数据，下次安装自动沿用
- **完全卸载**：删除全部配置和数据（含 token），不可恢复

## GitHub Actions 云构建

仓库已配置 `build-spk.yml` workflow（手动触发）：

1. Actions → **Build Komari Agent SPK** → Run workflow
2. 参数：
   - `version`：komari-agent 版本 tag，如 `1.2.60`（留空 = 使用 `VERSION` 文件）
   - `archs`：架构（默认 `x86_64 armv7 armv8`）
3. 构建成功自动发布 GitHub Release，附带三架构 `.spk` 与 SHA256

也可通过推送 tag 触发：`git tag v1.2.60-1 && git push origin v1.2.60-1`

版本号规则：`{komari 版本}-{SPK 修订}`，如 `1.2.60-1`。Agent 版本不变时递增修订号，上游升级时跟随其版本。

## 本地构建

前置：Linux x86_64 主机，root/sudo 权限，`git`、`python3`、`xz-utils`、`curl`/`wget`。

```bash
make download    # 下载并校验上游二进制（SHA256）
make package     # 原生运行 Synology pkgscripts-ng 构建（需 sudo）
make test        # 静态 / 解包 / 架构检查
make all         # download + package + test 一条龙
```

产物在 `dist/*.spk`。构建环境（每架构 chroot 约 6-7 GB）用后自动清理；已有 Toolkit tar 包缓存时放入 `/toolkit/toolkit_tarballs/` 可跳过下载。

## 目录结构

```
komari-agent/
├── Makefile                 # download / package / test / all
├── VERSION                  # 格式: <上游Agent版本>-<SPK修订>，如 1.2.60-1
├── INFO.sh                  # 生成 INFO 元数据（版本读取自 VERSION）
├── SHA256SUMS               # 上游官方二进制 SHA256（fallback 校验）
├── config/config.example.json  # 配置模板
├── conf/
│   ├── privilege            # run-as: package 专用套件用户
│   └── resource
├── scripts/                 # 套件生命周期脚本
│   ├── preinst / postinst / preuninst / postuninst
│   ├── preupgrade / postupgrade
│   ├── start-stop-status    # 启停 / 状态 / 日志轮转守护
│   └── wizard-config.sh     # 安装/升级时应用配置值、固定 disable_auto_update
├── WIZARD_UIFILES/uninstall_uifile  # 卸载选项（保留/删除配置）
├── SynoBuildConf/install    # Pack Stage 主脚本
├── tools/
│   ├── download-agent.sh    # 下载上游二进制 + SHA256 校验
│   └── build_spk_native.sh  # 原生 Toolkit 构建（chroot）
├── ui/                      # 配置窗口（dsmuidir）
│   ├── config               # 应用窗口入口（ExtJS app）
│   ├── Main.js              # 弹窗窗口（iframe 内嵌配置页）
│   ├── index.html           # JSON 编辑器页面
│   ├── config.cgi           # 配置读写 / 校验 / 重启后端
│   └── images/              # 图标
└── tests/check_static.sh    # 静态 / 解包 / 架构检查
```

## 相关链接

- 上游项目：[komari-monitor/komari-agent](https://github.com/komari-monitor/komari-agent)
- 本仓库：[inxen/komari-agent-spk](https://github.com/inxen/komari-agent-spk)

## License

本套件（packaging layer）采用 [MIT License](./LICENSE)。打包的 Komari Agent 二进制为上游未修改的官方 Release，遵循上游 [MIT License](https://github.com/komari-monitor/komari-agent/blob/main/LICENSE)。

- 开发者：Komari 社区
- 发布者：inxen