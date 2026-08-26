# Komari Agent Synology SPK

将开源监控 Agent **Komari Agent** 封装为可在 Synology DSM 7.x Package Center 中安装、启动、停止、升级和卸载的 `.spk` 软件包。

这是一个 **非常薄的 Synology packaging layer**。它不修改 Komari Agent 核心代码，而是直接打包上游官方 Release 二进制，让用户可以像安装普通第三方套件一样使用 Komari Agent，无需 SSH 手工下载二进制、创建 init 脚本或配置开机自启。

> **本项目是 SPK packaging project。** Komari Agent 本身属于上游项目：
> https://github.com/komari-monitor/komari-agent

---

## 目录

- [项目用途](#项目用途)
- [支持的 DSM 版本](#支持的-dsm-版本)
- [支持的 NAS 架构](#支持的-nas-架构)
- [目录结构](#目录结构)
- [安装方法](#安装方法)
- [配置方法](#配置方法)
- [启动 / 停止方法](#启动--停止方法)
- [配置文件位置](#配置文件位置)
- [日志位置](#日志位置)
- [升级方式](#升级方式)
- [卸载行为](#卸载行为)
- [Agent 自动更新策略](#agent-自动更新策略)
- [自行构建 SPK](#自行构建-spk)
- [添加新的架构](#添加新的架构)
- [自动化测试](#自动化测试)
- [真机测试清单](#真机测试清单)
- [License](#license)

---

## 项目用途

让 Komari Monitor 的 Agent 可以直接在 DSM Package Center 中安装和运行。安装后 Agent 自动启动，并在 DSM 重启后自动恢复，向 Komari Server 上报 CPU / 内存 / 磁盘 / 网络等系统数据。

## 支持的 DSM 版本

- **DSM 7.x**（`os_min_ver="7.0-40000"`）

## 支持的 NAS 架构

本项目按 Synology 官方 **platform family** 打包（见 `INFO.sh` 使用 `pkg_get_platform_family`）。Komari Agent 是纯用户态**静态链接** Linux 程序（官方 `CGO_ENABLED=0 go build -trimpath`），无内核特定依赖，因此同一架构族的所有模型可以共用同一个 SPK。

| SPK 架构 (arch) | 上游 Agent 二进制 | 典型平台 / 模型示例 |
| --- | --- | --- |
| `x86_64` | `komari-agent-linux-amd64` | bromolow, cedarview, avoton, braswell, denverton, apollolake, geminilake, v1000 ...（如 DS220+, DS920+, DS923+） |
| `armv7` | `komari-agent-linux-arm` | alpine, alpine4k（如 DS1517, DS1817） |
| `armv8` | `komari-agent-linux-arm64` | rtd1296, armada37xx, rtd1619, rtd1619b（如 DS218, DS220j, DS423） |

> **说明**：Synology 官方 Toolkit 中 ARM 64 位的 arch family 值是 **`armv8`**（不是 `arm64`），见 [Appendix A: Platform and Arch Value Mapping Table](https://help.synology.com/developer-guide/appendix/platarchs.html)。本项目遵循官方映射。

## 目录结构

```
komari-agent-synology/
├── README.md
├── LICENSE
├── Makefile
├── VERSION                  # 格式: <上游Agent版本>-<SPK修订>，如 1.2.60-1
├── INFO.sh                  # 生成 INFO 文件（Pack Stage 用）
├── SHA256SUMS               # 上游官方二进制 SHA256（fallback 校验）
├── config/
│   └── config.example.json  # 配置模板
├── scripts/                 # Package Center 生命周期脚本
│   ├── preinst
│   ├── postinst
│   ├── preuninst
│   ├── postuninst
│   ├── preupgrade
│   ├── postupgrade
│   ├── start-stop-status
│   └── wizard-config.sh      # 应用 DSM 向导值的共享助手
├── WIZARD_UIFILES/          # DSM 卸载向导（保留/删除配置选项）
│   └── uninstall_uifile
├── conf/
│   ├── privilege            # DSM 7 权限模型（run-as: package）
│   └── resource
├── SynoBuildConf/
│   ├── depends
│   ├── build
│   └── install              # Pack Stage 主脚本
├── PACKAGE_ICON.PNG
├── PACKAGE_ICON_256.PNG
├── tools                    # 下载 / 原生 Toolkit 构建脚本
│   ├── download-agent.sh    # 下载上游二进制 + SHA256 校验
│   └── build_spk_native.sh  # 原生构建 SPK 入口（chroot，需 root）
└── tests/
    └── check_static.sh      # 静态 / 解包 / 架构检查
```

## 安装方法

1. 在 Synology Package Center → 右上角“设置” → “信任层级” → 选择允许安装未签名套件（或“Synology 及第三方”）。
2. 点击“手动安装”，选择构建好的 `.spk` 文件。
3. 安装全程静默（无向导），安装完成后 Komari Agent 自动启动。

> 未签名套件需要开启“信任任何发行者”才能从第三方来源安装，请自行评估安全风险。

## 配置方法

### 方式一：DSM 原生配置窗口（弹窗，推荐）

套件提供 **DSM 原生风格配置窗口**，在 DSM 界面内以弹窗打开，无需 SSH、无需额外端口、不会打开新页面。

**入口**：安装后在 Package Center 打开 Komari Agent，DSM 会在界面内弹出原生配置窗口。

**实现**：基于 DSM 官方套件 UI 机制（`dsmuidir` + `type: "app"` 应用窗口），用 Vue + webpack 构建 DSM 原生窗口（Bundle.js），由 DSM 自己的 Web 服务器加载，不依赖任何额外 HTTP 端口。

**功能**：
- **完整 JSON 编辑器**：直接编辑 `config.json` 全部字段
- **恢复默认**：载入当前版本的默认配置（不保存）
- **撤销修改**：放弃未保存修改，恢复到最近一次保存的配置
- **保存配置**：校验 JSON → 原子写入（写临时文件→校验→替换）→ 显示结果
- **应用配置**：保存后重启 Agent，并显示运行结果

**安全**：
- 配置窗口要求 DSM 登录会话（sid）+ CSRF token（synotoken）双重校验
- token 不进入 URL、日志或命令行参数
- `config.json` 权限 600，属主为运行用户 `sc-KomariAgent`
- 原子写入避免保存中断损坏配置

### 方式二：安装静默 + 卸载选项

**安装、升级、覆盖安装均完全静默**（不弹任何配置向导），`config.json` 在升级/覆盖时自动保留（`preinst` 备份 + `postinst` 恢复），避免每次都要重新填写参数。配置统一在 DSM 配置窗口或 SSH 中完成。

**卸载时弹出选项**（`WIZARD_UIFILES/uninstall_uifile`）：
- **仅卸载**：保留配置和数据，方便以后重新安装时沿用
- **删除所有配置和数据**：不可恢复

### 方式三：SSH 编辑配置文件

通过 SSH 编辑：

```
/var/packages/KomariAgent/var/config.json
```

编辑后重启套件：

```bash
synopkg restart KomariAgent
```

或通过 Package Center 停止再启动。

**首次安装**会创建一个默认 `config.json`（内容来自 `config.example.json`）。其中 `disable_auto_update` 默认设为 `true`（原因见 [Agent 自动更新策略](#agent-自动更新策略)）。你只需填入 `endpoint` 和 `token`：

```json
{
  "endpoint": "https://your-komari-server.example.com",
  "token": "your-agent-token",
  "interval": 3,
  "disable_auto_update": true
}
```

支持的配置项以当前上游版本为准（`komari-agent --help` 或上游 [readme.md](https://github.com/komari-monitor/komari-agent/blob/main/readme.md)）。常见字段：

| JSON 字段 | 说明 |
| --- | --- |
| `endpoint` | 面板地址 |
| `token` | agent token |
| `interval` | 数据采集间隔（秒） |
| `disable_auto_update` | 禁用 Agent 自身自动更新 |
| `disable_web_ssh` | 禁用远程控制（web ssh / rce） |
| `ignore_unsafe_cert` | 忽略不安全证书 |
| `include_nics` / `exclude_nics` | 网卡过滤（逗号分隔） |
| `include_mountpoints` | 挂载点过滤（分号分隔） |
| `month_rotate` | 流量月重置日期，0 禁用 |
| `auto_discovery_key` | 自动发现密钥 |
| `custom_dns` | 自定义 DNS |
| `enable_gpu` | 启用详细 GPU 监控 |
| `protocol_version` | 上报协议版本（默认 2） |
| `disable_compression` | 禁用 v2 压缩 |
| `prefer_ip_version` | 4 或 6 |

## 启动 / 停止方法

通过 Package Center 操作，或命令行：

```bash
synopkg start KomariAgent
synopkg stop KomariAgent
synopkg restart KomariAgent
synopkg status KomariAgent
```

开机自启由 Package Center 的 `start-stop-status` 机制负责（不创建 systemd service）。

## 配置文件位置

- 程序目录：`/var/packages/KomariAgent/target/`
- 数据 / 配置目录：`/var/packages/KomariAgent/var/`
  - `config.json`（用户配置，升级保留）
  - `log/komari-agent.log`（Agent 运行日志，自动轮转）
  - `data/`（Agent 数据）

`config.json` 权限为 `600`，避免 token 被其他用户读取。

## 权限说明

DSM 7.0 起 **强制包降权运行**（`packages are forced to lower the privilege`），以 root 权限运行的第三方套件会被 Package Center 直接拒绝安装。因此本包以普通用户运行（`conf/privilege` 中 `run-as: package`），运行用户为 `sc-KomariAgent`。

Komari Agent 通过 gopsutil 采集系统数据，而这些数据主要来自 `/proc`（`/proc/stat`、`/proc/meminfo`、`/proc/net/dev`、`/proc/diskstats`、`/proc/mounts`）和 `/sys/block` 等文件，**这些文件对普通用户可读**。已在 Debian 上以非 root 用户实测确认：CPU、内存、磁盘、网络、挂载点等核心监控数据均可在普通用户下正常读取。因此使用 `package` 用户运行既能满足 DSM 7 的安装要求，又不影响核心监控功能。

本包不请求额外系统资源（`conf/resource` 为空 `{}`），未设置 capabilities，未开放端口。

## 日志策略

与上游官方行为一致：Agent 始终输出日志，由启动脚本重定向到文件：

- 日志位置：`/var/packages/KomariAgent/var/log/komari-agent.log`
- 正常连接面板时日志量极小（仅启动信息）；面板失联时约 7 MB/天
- **自动轮转**：超过 10 MiB 轮转并保留 3 份备份（`komari-agent.log.1` ~ `.3`）
- 服务运行期间有后台守护轮转（每 5 分钟检查一次），磁盘占用上限约 **40 MiB**，不会无限增长

## 升级方式

在 Package Center 手动安装更高版本的 `.spk` 即可。升级流程（`preupgrade` / `postupgrade`）：

1. 停止旧 Agent。
2. 备份 `var/`（含 `config.json`）到临时升级目录。
3. 替换程序文件 / 二进制。
4. 恢复 `var/`（config 不丢失）。
5. 启动新 Agent。

版本号约定：

```
1.2.60-1
└─────┘ └┘
 上游    SPK 修订
```

- `1.2.60-1` → `1.2.60-2`：Agent 版本不变，SPK 打包修复。
- `1.2.60-1` → `1.2.61-1`：上游 Agent 升级。

## 卸载行为

卸载时：停止 Agent，删除程序文件、PID、临时文件。

**卸载向导会询问保留还是删除配置数据**（`WIZARD_UIFILES/uninstall_uifile`，单选）：

- **仅卸载（保留配置）**：保留 `config.json`、日志和用户数据，方便后续重装。
- **删除所有配置和数据**：彻底删除（不可恢复）。

如需手动彻底清除：

```bash
rm -rf /var/packages/KomariAgent/var
```

## Agent 自动更新策略

**原则：Package Center 管理版本 > Agent 自己更新。**

上游 Agent 的自动更新（`update.CheckAndUpdate` / `DoUpdateWorks`）会**就地覆盖当前可执行文件**并 `os.Exit(42)` 重启，这会破坏 SPK 管理的二进制，导致“SPK 显示 1.2.60，实际运行 1.2.61”的版本不一致。

因此本项目默认在 `config.json` 中设置 `"disable_auto_update": true`，由 SPK 升级负责 Agent 版本更新。

## 自行构建 SPK

### 已验证事项

- 上游 v1.2.60 的三个 Linux 二进制（`linux-amd64` / `linux-arm64` / `linux-arm`）已下载并校验，SHA256 与 GitHub Release 官方 digest 一致。
- 三者均为**静态链接** ELF：`ELF64 x86-64`、`ELF64 AArch64`、`ELF32 ARM`（与上游 `CGO_ENABLED=0 go build -trimpath` 一致），因此可安全按 platform family 分发。

### 前置条件

- Linux 主机（x86_64），具备 root/sudo 权限（Synology Toolkit 在 chroot 中构建）
- `git`、`python3`、`xz-utils`、`curl`/`wget`
- 网络（下载上游二进制 + Synology Toolkit 环境；约 3GB 磁盘缓存 + 每架构 6-7GB chroot，构建完自动清理）

### 构建方式（原生 Toolkit，无需 Docker）

```bash
# 1. 下载并校验上游二进制（SHA256）
make download

# 2. 构建 SPK（原生运行 Synology pkgscripts-ng，需要 sudo）
make package

# 3. 静态检查
make test

# 4. 一条命令完成 download -> package -> test
make all
```

产物在 `dist/*.spk`。

> **说明**：`make package` 会自动把 Synology `pkgscripts-ng`（DSM7.4 分支）克隆到 `/toolkit/pkgscripts-ng`（若不存在），然后以 root 运行 `tools/build_spk_native.sh`。每个架构的 chroot 构建环境用完即删，磁盘占用保持在单个 chroot 的水平。
>
> 若已有本地 Toolkit tar 包缓存（`base_env-7.4.txz` 与 `ds.<平台>-7.4.{env,dev}.txz`），放到 `/toolkit/toolkit_tarballs/` 可跳过下载：
>
> ```bash
> sudo TOOLKIT_DIR=/toolkit bash tools/build_spk_native.sh x86_64 armv7 armv8
> ```

### 仅下载 + 静态检查（无 Toolkit）

```bash
make download   # 下载二进制并校验 SHA256
make test       # 静态 / 解包 / 架构检查（需要一个已构建的 .spk）
```

### 手工下载单个二进制

```bash
./tools/download-agent.sh 1.2.60 amd64   # 版本 架构(amd64|arm64|arm)
```

## 添加新的架构

1. 在 `SynoBuildConf/install` 的 family→asset 映射中，把上游二进制名映射到新的 family（如增加 `loong64`）。
2. 在 `tools/build_spk_native.sh` 的 `PLATFORM_BY_FAMILY` 增加 family→chroot 平台映射。
3. 在 `Makefile` 的 `ARCHS` 增加架构。
4. 运行 `make download`（会更新 SHA256SUMS / 校验）和 `make package`。
5. 在 `tests/check_static.sh` 的架构检查中增加 `file` 匹配规则。

## 自动化测试

```bash
make test        # = bash tests/check_static.sh dist
```

覆盖：

- **静态测试**：SPK / INFO / package.tgz / scripts / start-stop-status 可执行 / Agent binary 可执行。
- **架构测试**：`file` 确认 SPK 内 binary 架构与 SPK 名称匹配（x86_64 / armv8 / armv7）。
- **Shell 测试**：`shellcheck scripts/* tools/*`（若安装了 shellcheck）。
- **SPK 解包测试**：`tar` 解包 `.spk`，检查 `INFO` / `package.tgz` / `scripts`。
- **Agent 测试**：对本地 `downloads/` 中的二进制执行 `--help` / `--version`（若与宿主架构兼容）。

## 真机测试清单

在真实 Synology DSM 7.x 上验证（见需求文档 §23）：

1. DSM 7.x 安装 / Package Center 显示
2. 安装、启动、停止、重启成功
3. NAS 重启后自动启动
4. Agent 连接 Komari Server
5. CPU / 内存 / 磁盘 / 网络数据正常
6. 配置修改后生效
7. SPK 升级（配置保留）
8. SPK 卸载 + 重装（配置保留）
9. Agent 异常退出后行为正常

## License

本项目（packaging layer）采用 [MIT License](./LICENSE)。打包的 Komari Agent 二进制为上游未修改的官方 Release，遵循上游 [MIT License](https://github.com/komari-monitor/komari-agent/blob/main/LICENSE)。

- 上游项目：https://github.com/komari-monitor/komari-agent
- 本项目：Komari Agent Synology SPK packaging project
