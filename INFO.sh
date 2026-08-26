#!/bin/bash
# shellcheck disable=SC2034
# shellcheck source=/dev/null
#
# INFO.sh - define the metadata for the Komari Agent Synology package.
#
# This file is SOURCED by SynoBuildConf/install during the Pack Stage, which
# then calls pkg_dump_info to emit the INFO file. It sources the official
# pkg_util.sh so that pkg_get_platform_family and pkg_dump_info are available.
#
# We use pkg_get_platform_family because Komari Agent is a pure user-space
# static Linux binary with no kernel-specific dependency. This lets a single
# package install on every Synology model sharing the same architecture
# family (e.g. arch=x86_64 installs on bromolow/cedarview/denverton/...).
#
# NOTE: It intentionally does NOT use pkg_get_spk_platform, which would
# restrict the package to a single model platform.

source /pkgscripts-ng/include/pkg_util.sh

# Package identity
package="KomariAgent"
# Single source of truth: the VERSION file ("<upstream>-<packaging rev>",
# e.g. 1.2.60-2), shared with tools/download-agent.sh and the CI workflow.
# During the Pack Stage the working directory is the project root.
version="$(tr -d '[:space:]' < "$(pwd)/VERSION" 2>/dev/null)"
[ -n "$version" ] || version="0.0-0"
displayname="Komari Agent"
maintainer="Komari 社区"
distributor="inxen"
# Links shown in Package Center: upstream project (developer) and this
# packaging repo (distributor).
maintainer_url="https://github.com/komari-monitor/komari-agent"
distributor_url="https://github.com/inxen/komari-agent-spk"
description="Komari Monitor Agent for Synology DSM. A thin packaging layer around the upstream komari-agent (komari-monitor/komari-agent)."
description_chs="Komari 监控 Agent（Synology DSM 套件）。

【配置方法】
1. 安装或升级套件时，在弹出的向导中填写服务器地址、Agent Token 等参数。
2. 如需修改配置，编辑配置文件：
   /var/packages/KomariAgent/var/config.json
   保存后执行：synopkg restart KomariAgent

【常用配置项】
endpoint: 面板地址
token: agent token
interval: 数据采集间隔（秒）
disable_web_ssh: 禁用远程控制
disable_auto_update: 禁用自动更新（套件默认启用）

【日志位置】
/var/packages/KomariAgent/var/log/komari-agent.log
超过 10MB 自动轮转并保留 3 份备份（磁盘占用上限约 40MB），不会无限增长。

【卸载】
卸载时会询问是否保留配置和数据。"
description_cht="Komari 監控 Agent（Synology DSM 套件）。

【設定方式】
1. 安裝或升級套件時，在精靈中填寫伺服器位址、Agent Token 等參數。
2. 若要修改設定，編輯設定檔：
   /var/packages/KomariAgent/var/config.json
   儲存後執行：synopkg restart KomariAgent

【常用設定項】
endpoint: 面板位址
token: agent token
interval: 資料收集間隔（秒）
disable_web_ssh: 停用遠端控制
disable_auto_update: 停用自動更新（套件預設啟用）

【日誌位置】
/var/packages/KomariAgent/var/log/komari-agent.log
超過 10MB 自動輪轉並保留 3 份備份（磁碟佔用上限約 40MB），不會無限增長。

【解除安裝】
解除安裝時會詢問是否保留設定和資料。"
support_url="https://github.com/komari-monitor/komari-agent"
thirdparty="yes"
startable="yes"
# DSM UI: package's own web UI lives in target/ui (served by DSM's own nginx on
# the DSM port, no extra port required). dsmappname is the App Config name used
# by the Package Center "open" button to launch the configuration page.
dsmuidir="ui"
dsmappname="SYNO.SDS.App.KomariAgent.Instance"
# No install/upgrade wizard: installation, upgrade and overwrite-reinstall are
# fully silent so nothing prompts for config each time (DSM cannot distinguish
# first install from a reinstall - the wizard is static). Configuration is done
# in the DSM config window ("打开") or by editing config.json. Uninstall keeps
# a wizard (silent_uninstall="no") offering keep-vs-delete of config/data.
silent_install="yes"
silent_upgrade="yes"
silent_uninstall="no"
os_min_ver="7.0-40000"

# Architecture family. Build the SPK per architecture family so a single
# static binary covers all models of the same architecture.
arch="$(pkg_get_platform_family)"
