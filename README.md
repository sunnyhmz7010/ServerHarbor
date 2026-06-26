<div align="center">
  <h1>ServerHarbor</h1>
  <p>面向 Linux 多服务器场景的轻量级 Shell 运维工具集，把新机开荒、安全卫士与节点管理整合到一个交互式菜单里</p>
</div>

<p align="center">
  <a href="https://github.com/sunnyhmz7010/ServerHarbor/releases"><img src="https://img.shields.io/github/v/release/sunnyhmz7010/ServerHarbor?label=Release&color=3b82f6" alt="Release" /></a>
  <a href="https://github.com/sunnyhmz7010/ServerHarbor/blob/main/LICENSE"><img src="https://img.shields.io/github/license/sunnyhmz7010/ServerHarbor?color=10b981" alt="License" /></a>
</p>

<p align="center">
  <a href="https://github.com/sunnyhmz7010/ServerHarbor/releases">下载源码</a> ·
  <a href="https://github.com/sunnyhmz7010/ServerHarbor/issues">反馈问题</a>
</p>

---

## ✨ 为什么做这个项目

多服务器运维里最常重复、也最容易出错的，往往不是复杂平台本身，而是那些高频基础动作：新服务器初始化、节点连通性检查、系统安全巡检、基础加固和结果留档。

ServerHarbor 的目标，就是用一个可以直接在 Linux 上运行的 Shell 项目，把这些高频操作做成统一入口，既适合课程展示，也适合后续继续扩展。

- 用交互式菜单整合多服务器常见运维任务
- 保持每台节点都可以独立执行，不依赖固定主节点
- 保持脚本结构清晰，便于后续继续增加更细的巡检或开荒动作

## 🚀 核心能力

### 🖥️ 系统开荒

- 安装常用基础工具（curl、socat、wget、sudo、iptables）
- Docker 安装（自动检测地区，中国使用阿里云镜像）
- 集成 [bbrv3-lite](https://github.com/ike-sh/bbrv3-lite) 和 [vps-tcp-tune](https://github.com/Eric86777/vps-tcp-tune) 网络调优脚本
- 生成详细的系统开荒报告（CPU、内存、磁盘、网络、状态摘要）

### 🛡️ 安全卫士

- 失败登录统计与来源 IP 排行
- 可疑 Web 请求扫描（SQL 注入、路径遍历等）
- 防火墙状态查看与规则摘要
- 文件完整性基线生成与校验
- 安全评分计算（100 分制，含扣分项与修复建议）
- 综合安全巡检报告

### 🛰 节点管理

- 通过 JSON 配置文件管理节点
- 测试节点 SSH 连通性
- 检查节点 ICMP、SSH 端口和延迟
- 批量在选中节点上执行命令
- 将配置文件同步到选中节点
- 部署 SSH 密钥到选中节点
- 生成一键加入命令

## ⚡ 快速开始

### 📋 前置要求

- Linux 服务器或支持 Bash 的 Linux 环境
- 需要 `root` 权限执行开荒、加固等操作

检查本机 curl：

```bash
curl --version
```

如果未安装，请先执行：

```bash
apt update -y && apt install curl -y
```

### 📦 使用方式

1. 克隆仓库

```bash
git clone https://github.com/sunnyhmz7010/ServerHarbor.git
cd ServerHarbor
```

2. 赋予执行权限并启动

```bash
chmod +x menu.sh
./menu.sh
```

### 📋 主菜单结构

```
[1] 🚀 系统开荒     基础软件 / Docker / 网络调优脚本
[2] 🛡 安全卫士     认证日志 / Web 攻击 / 防火墙 / 完整性 / 安全评分
[3] 🛰 节点管理     节点管理 / 批量命令 / 配置同步 / 加入命令
[4] ♻️ 更新         下载最新源码并重启
[5] 🗑 卸载         从系统中移除 ServerHarbor（仅安装版）
[0] ↩ 退出
```

3. 首次使用前，建议先检查配置

- `/opt/serverharbor/data/serverharbor.conf`

### 💻 一条命令直接运行

```bash
bash <(curl -q -fsSL "https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/run.sh?$(date +%s)")
```

在线运行入口会先展示将执行的动作，再请求确认；确认前不会创建临时目录、下载源码包或尝试安装依赖。

### 📥 一条命令安装

```bash
curl -q -fsSL "https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/install.sh?$(date +%s)" | sudo bash
```

安装器会在执行任何包安装、目录创建或文件写入之前，先展示计划动作并请求确认。

安装与更新默认只依赖 `bash`、`curl` 和 `tar`。

安装完成后可直接执行：

```bash
shr
```

安装代码目录：

```text
/opt/serverharbor/app
```

运行数据与用户配置目录：

```text
/opt/serverharbor/data
```

快捷命令：

```text
/usr/local/bin/shr
```

## 📖 使用说明

### 1. 🚀 启动菜单

执行：

```bash
./menu.sh
```

主菜单包含：

- `1` 系统开荒
- `2` 安全卫士
- `3` 节点管理

### 2. 🖥️ 系统开荒

在菜单中选择 `1`，可执行：

- 基础软件安装
- Docker 安装
- bbrv3-lite / vps-tcp-tune 网络调优
- 系统状态查看
- 生成详细开荒报告（CPU、内存、磁盘、网络、摘要）

### 3. 🛡️ 安全卫士

在菜单中选择 `2`，可执行：

- 生成综合安全报告
- 查看失败登录统计
- 查看可疑 Web 请求
- 查看防火墙状态
- 创建/校验文件完整性基线
- 管理监控路径
- 计算安全评分

每个功能都有美化输出：分块展示、对齐的键值对、状态指示和操作建议。

### 4. 🛰 节点管理

在菜单中选择 `3`，可执行：

- 列出、添加、删除节点
- 测试选中节点的 SSH 连通性
- 探测所有节点的 ICMP、SSH、延迟
- 在选中节点上批量执行命令
- 将配置文件同步到选中节点（支持按节点设不同路径）
- 部署 SSH 密钥到选中节点
- 生成一键加入命令

批量操作支持选择特定节点，不固定为"所有节点"。

## 🧠 功能细节

### 📁 脚本结构

- `menu.sh` 负责菜单与 CLI 入口
- `common.sh` 负责共享变量、日志与配置加载
- `bootstrap.sh` 负责系统开荒
- `nodes.sh` 负责节点管理（含探测、批量操作、加入命令）
- `security.sh` 负责安全巡检

### 📊 报告与状态文件

- 探测、安全、开荒报告输出到 `reports/`
- 节点状态与完整性基线保存在 `state/`
- 运行日志输出到 `logs/`

### 🔒 本地优先

- 不依赖专用控制面
- 不引入额外组网工具作为前置条件
- 以 Shell、SSH 和系统自带能力为核心
- 保持轻量，方便在普通 Linux 服务器上直接运行

## 🧱 技术栈

- Shell：Bash
- 系统工具：`curl`、`tar`、`ssh`、`sha256sum`、`jq`
- 目标平台：Linux

## 🗂️ 项目结构

```text
ServerHarbor/
├─ menu.sh                      # 交互式菜单入口与 CLI 模式
├─ common.sh                    # 共享变量、日志、配置加载、通用函数
├─ bootstrap.sh                 # 系统开荒（基础软件、Docker、网络调优）
├─ nodes.sh                     # 节点管理（JSON 配置、SSH、探测、批量操作）
├─ security.sh                  # 安全巡检（登录、Web 攻击、防火墙、完整性）
├─ serverharbor.conf            # 默认配置文件
├─ install.sh                   # 安装脚本
├─ run.sh                       # 在线运行脚本
├─ uninstall.sh                 # 卸载脚本
├─ README.md                    # 项目说明
├─ AGENTS.md                    # 仓库协作与工程规则
├─ SECURITY.md                  # 安全报告策略
├─ CODE_OF_CONDUCT.md           # 社区行为准则
└─ LICENSE                      # GPL-3.0 许可证
```

## 👨‍💻 本地开发

### 🧰 环境

- Bash
- Linux 常见系统工具链
- jq（节点管理功能需要，首次使用时自动安装）

### ✅ 语法检查

```bash
bash -n menu.sh common.sh bootstrap.sh security.sh nodes.sh install.sh run.sh uninstall.sh
```

### ▶️ 交互运行

```bash
./menu.sh
```

### ⚙️ CLI 模式

```bash
./menu.sh --cron-probe      # 定时节点探测
./menu.sh --cron-security   # 定时安全检查
./menu.sh --cron-alerts     # 定时告警检查
```

### 🗑️ 卸载

```bash
curl -q -fsSL "https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/uninstall.sh?$(date +%s)" | sudo bash
```

卸载脚本会先检查安装清单，仅删除 ServerHarbor 自己创建和管理的内容，不会无条件清理其他同名文件。

### 🔍 仓库检查

```bash
git status
rg "pattern" .
```

## 🔐 安全报告

如果发现安全问题，请不要公开披露细节。请优先参考仓库中的 [SECURITY.md](./SECURITY.md) 提交安全报告。

## 📄 许可证

本项目基于 [GPL-3.0](./LICENSE) 开源。

## ⭐ 星标历史

[![Star History Chart](https://api.star-history.com/svg?repos=sunnyhmz7010/ServerHarbor&type=Date)](https://star-history.com/#sunnyhmz7010/ServerHarbor&Date)

<div align="center">
  <sub>Built with ❤️ by Sunny</sub>
</div>
