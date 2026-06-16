<div align="center">
  <h1>ServerHarbor</h1>
  <p>面向 Linux 多服务器场景的轻量级 Shell 运维工具集，把新机开荒、节点探测、安全巡检、备份轮转和 GitHub 状态同步整合到一个交互式菜单里</p>
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

多服务器运维里最容易重复、最容易出错的，往往不是复杂平台本身，而是每天都要手动做的那些小事：新服务器初始化、巡检、日志查看、基础安全检查、备份打包、状态留档。

ServerHarbor 的目标，就是用一个可直接在 Linux 上运行的 Shell 项目，把这些高频基础操作做成统一入口，既适合真实练习，也适合作为《Linux 编程》课程项目持续扩展。

- 用交互式菜单整合多服务器常见运维任务
- 让每台节点都能独立执行探测、备份和状态同步，不依赖固定主节点
- 用 GitHub 保存运行状态、报告和配置演进，方便留档与展示
- 保持脚本结构清晰，便于后续继续增加互备、加入命令和网络模式判断

## 📸 截图预览

当前仓库暂未放置界面截图。后续可补充终端菜单、探测报告和备份执行结果截图。

## 🚀 核心能力

### 🧭 交互式运维入口

- 通过 `menu.sh` 提供统一菜单界面
- 用户可以直接输入 `1` 到 `9` 选择功能模块
- 将开荒、巡检、安全、备份、Git 同步和定时任务集中到一个入口
- 适合课程展示时逐项演示功能

### 🖥️ 新服务器开荒

- 安装常用基础工具
- 配置 BBR、DNS、swap 和时区
- 提供基础 SSH 加固能力
- 自动生成开荒报告，记录当前主机初始化结果

### 🌐 多节点探针

- 通过 `config/peers.conf` 管理对等节点
- 支持采集本机状态并探测其他节点连通性
- 输出节点探测报告，记录 ICMP、SSH 端口和基础状态信息
- 每个节点都可以独立执行，不依赖固定主从结构

### 🔐 基础安全管理

- 统计失败登录来源 IP
- 扫描常见 Web 攻击访问痕迹
- 查看本机监听端口与防火墙状态
- 支持生成文件完整性校验基线并进行比对

### 💾 备份与同步

- 根据 `config/watch.conf` 定义重要目录
- 自动打包配置、站点或数据目录
- 清理超过保留天数的历史备份
- 支持将最新备份同步到其他节点

### 📝 GitHub 状态留档

- 初始化 Git 仓库并绑定 GitHub 远端
- 将状态文件、巡检报告和配置变更纳入版本管理
- 支持手动提交与推送
- 支持通过 `cron` 定时自动推送最新状态

## ⚡ 快速开始

### 📋 运行要求

- Linux 服务器或支持 Bash 的 Linux 环境
- 建议具备 `bash`、`git`、`ssh`、`rsync`、`cron` 等常用工具
- 开荒、swap、DNS、SSH 加固、防火墙相关功能通常需要 `root` 权限

检查 Bash 与 Git：

```bash
bash --version
git --version
```

### 📦 使用方式

1. 克隆仓库：

```bash
git clone https://github.com/sunnyhmz7010/ServerHarbor.git
cd ServerHarbor
```

2. 赋予执行权限并启动：

```bash
chmod +x menu.sh
./menu.sh
```

3. 首次使用前，建议先修改：

- `/opt/serverharbor/data/config/app.conf`
- `/opt/serverharbor/data/config/peers.conf`
- `/opt/serverharbor/data/config/watch.conf`

### ⚡ 一条命令直接运行

像 `bbrv3-lite` 一样，ServerHarbor 也支持直接在线运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/run.sh)
```

### 📥 一条命令安装

安装到本机后，可直接使用 `shr` 命令启动：

```bash
curl -fsSL https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/install.sh | sudo bash
```

安装完成后：

```bash
shr
```

安装脚本会把项目放到：

```text
/opt/serverharbor/app
```

运行数据和用户配置放到：

```text
/opt/serverharbor/data
```

并仅创建一个受管快捷命令：

```text
/usr/local/bin/shr
```

## 📖 使用方式

### 1. 🧑‍💻 启动菜单

执行：

```bash
./menu.sh
```

主菜单支持：

- `1` 服务器开荒
- `2` 节点探测与健康报告
- `3` 安全巡检与基础加固
- `4` 备份与保留清理
- `5` 文件完整性基线与校验
- `6` Git 同步
- `7` 定时任务安装
- `8` 查看最新报告
- `9` 查看项目状态摘要

### 2. 🚀 新机开荒

在新服务器上进入菜单后，选择：

```text
1. Server bootstrap
```

可执行：

- 基础包安装
- 开启 BBR
- 配置 DNS
- 创建 swap
- SSH 基础加固
- 生成开荒报告

### 3. 🌐 节点探测

对等节点配置来自：

```text
config/peers.conf
```

示例结构：

```text
# alias,host
alpha,192.168.1.10
beta,192.168.1.11
```

运行探测后会：

- 检查节点 ICMP 是否可达
- 检查 22 端口是否开放
- 记录本机负载、内存、磁盘等快照
- 输出探测报告到 `reports/`

### 4. 🔐 安全巡检

安全模块支持：

- 失败登录统计
- 可疑 Web 请求扫描
- 防火墙状态查看
- 文件完整性基线创建与校验

完整性监控路径配置在：

```text
config/watch.conf
```

### 5. 💾 备份与轮转

备份模块会对 `watch.conf` 中定义的目录执行归档。

示例：

```bash
tar -czf backup.tar.gz /etc /var/www /root
```

实际运行时由脚本自动生成带时间戳的压缩包，并根据保留天数自动清理旧备份。

### 6. 📝 GitHub 同步

默认远端仓库为：

```bash
https://github.com/sunnyhmz7010/ServerHarbor
```

在菜单中选择 Git 模块后，可以：

- 初始化本地 Git 仓库
- 绑定远端地址
- 提交当前项目状态
- 推送到 GitHub

再次执行安装命令时：

- 如果未安装，会执行首次安装
- 如果已经安装，会提示当前已安装并拉取远端最新代码完成更新
- 本地用户配置和运行数据保留在 `/opt/serverharbor/data`，不会因为更新代码被覆盖

### 7. ⏱️ 定时执行

项目支持通过 `cron` 自动执行探测、安全报告、备份和 Git 推送。

安装定时任务后，脚本会使用：

- `--cron-probe`
- `--cron-security`
- `--cron-backup`
- `--cron-git`

这些 CLI 模式进行非交互执行。

## 🧠 功能细节

### 🗂️ 模块化脚本结构

- `menu.sh` 负责菜单与 CLI 入口
- `lib/common.sh` 负责共享变量、日志与配置加载
- `modules/` 按功能拆分为开荒、探测、安全、备份、Git、调度模块
- 配置与生成物分离，便于展示与维护

### 📄 报告与状态文件

- 探测、安全、备份、开荒报告输出到 `reports/`
- 节点状态与完整性基线保存在 `state/`
- 运行日志输出到 `logs/`
- 归档备份输出到 `backups/`

### 🔐 本地优先

- 不依赖专用控制面
- 不引入额外组网工具作为前置条件
- 以 Shell、SSH、rsync、git 和 cron 为核心
- 保持轻量，方便在普通 Linux 服务器上直接运行

## 🧱 技术栈

- Shell：Bash
- 系统工具：ssh、rsync、cron、tar、sha256sum
- 版本管理：Git
- 远端托管：GitHub
- 目标平台：Linux

## 🗂️ 项目架构

```text
ServerHarbor/
├─ menu.sh                      # 交互式菜单入口与 cron CLI 模式
├─ lib/
│  └─ common.sh                 # 共享变量、日志、配置加载、通用函数
├─ modules/
│  ├─ bootstrap.sh              # 新服务器开荒
│  ├─ probe.sh                  # 节点探测与本机状态采集
│  ├─ security.sh               # 安全巡检与完整性校验
│  ├─ backup.sh                 # 备份归档与同步
│  ├─ git_sync.sh               # Git 初始化、提交与推送
│  └─ scheduler.sh              # cron 定时任务安装
├─ config/
│  ├─ app.conf                  # 全局运行配置
│  ├─ peers.conf                # 对等节点配置
│  └─ watch.conf                # 备份与完整性监控路径
├─ reports/                     # 巡检、探测、开荒、备份报告
├─ state/                       # 节点状态和完整性基线
├─ backups/                     # 本地备份压缩包
├─ logs/                        # 运行日志
├─ .github/ISSUE_TEMPLATE/      # Issue 模板
├─ AGENTS.md                    # 仓库协作与工程规则
├─ SECURITY.md                  # 安全报告策略
├─ CODE_OF_CONDUCT.md           # 社区行为准则
├─ LICENSE                      # GPL-3.0 许可证
└─ README.md                    # 项目说明
```

## 👨‍💻 本地开发

### 🧰 环境

- Bash
- Git
- Linux 常见系统工具链

### 🔨 语法检查

```bash
bash -n menu.sh
```

### 🖥️ 交互运行

```bash
./menu.sh
```

### 📦 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/uninstall.sh | sudo bash
```

卸载脚本会先检查安装清单，仅删除 ServerHarbor 自己创建和管理的内容，不会无条件清理其他同名文件。

### ✅ 仓库检查

```bash
git status
rg "pattern" .
```

## 🔐 安全报告

如果发现安全问题，请不要直接公开披露细节。请优先参考仓库中的 [SECURITY.md](./SECURITY.md) 提交安全报告。

## 📄 许可证

本项目基于 [GPL-3.0](./LICENSE) 开源。

## ⭐ 星标历史

[![Star History Chart](https://api.star-history.com/svg?repos=sunnyhmz7010/ServerHarbor&type=Date)](https://star-history.com/#sunnyhmz7010/ServerHarbor&Date)

<div align="center">
  <sub>Built with ❤️ by Sunny</sub>
</div>
