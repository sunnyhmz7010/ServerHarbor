# AGENTS.md

## 项目概况

ServerHarbor 是一个基于 Bash 的 Linux 多服务器运维工具箱，面向运维学习者和管理员，提供轻量级的服务器初始化、分布式健康检查和安全巡检能力。

- 语言：`Bash`
- 平台：`Linux`
- 传输：`ssh`、`curl`、`tar`
- 仓库：`https://github.com/sunnyhmz7010/ServerHarbor`

### 入口文件

| 文件 | 用途 |
|------|------|
| `menu.sh` | 交互式主入口 |
| `run.sh` | 一键在线运行 |
| `install.sh` / `uninstall.sh` | 全局安装与卸载 |
| `common.sh` | 共享函数库 |
| `bootstrap.sh` | 系统初始化 |
| `security.sh` | 安全巡检 |
| `nodes.sh` | 节点管理 |
| `serverharbor.conf` | 默认配置（根目录） |

### 运行时路径

| 路径 | 说明 |
|------|------|
| `${NG_DATA_ROOT}/` | 运行时数据根目录（扁平结构） |
| `${NG_DATA_ROOT}/serverharbor.conf` | 运行时配置 |
| `${NG_DATA_ROOT}/state/` | 生成的状态文件 |
| `${NG_DATA_ROOT}/reports/` | 生成的报告 |
| `${NG_DATA_ROOT}/logs/` | 运行日志 |
| `/opt/serverharbor/app` | 安装模式代码目录 |
| `/opt/serverharbor/data` | 安装模式数据目录 |

## 菜单结构

主菜单（v1.0.0）：

- `[1]` 系统初始化 — 基础包、Docker、网络调优、系统状态、报告、数据迁移
- `[2]` 安全审计 — 安全报告、失败登录、Web 请求、防火墙、完整性基线/校验、监控路径、安全评分
- `[3]` 节点管理 — 节点列表、互信配置、远程执行
- `[4]` 更新
- `[5]` 卸载（仅安装模式）
- `[0]` 退出

CLI 模式：`--cron-probe`、`--cron-security`、`--cron-alerts`

## 架构约束

- 定位是 Shell 工具箱，不是完整编排平台；不引入集中式服务发现、共识或自动故障转移
- 零外部依赖，仅依赖 bash 和标准 Linux 工具（grep、awk、sed、ssh、curl、tar）
- 配置统一通过 `serverharbor.conf` 管理（KEY=VALUE + TSV 节点块）
- 禁止定义未被任何函数读取的配置变量，孤立变量必须删除
- 代码与用户数据解耦：安装更新可替换 `/opt/serverharbor/app`，但必须保留 `/opt/serverharbor/data`

### 在线模式与安装模式的数据隔离

- 在线模式（`curl | bash`）始终使用 `~/.config/serverharbor`，即使已安装
- 安装模式（`shr`）始终使用 `/opt/serverharbor/data`
- 两个数据目录完全独立，互不影响
- 安装器自动检测并提供在线数据迁移；迁移后源目录重命名为 `~/.config/serverharbor.migrated`
- 菜单 `[6]`（数据迁移）仅在安装模式下可见

### 运行时模型

- Bootstrap 和加固函数可能需要 root 权限
- 节点监控通过 `__NODES__` TSV 块驱动
- 完整性扫描通过 `NG_WATCH_PATHS` 驱动
- 安装器执行任何文件系统操作前必须打印意图并要求用户确认

## 开发规范

### 命令速查

```bash
# 语法检查
bash -n menu.sh common.sh bootstrap.sh security.sh nodes.sh install.sh run.sh uninstall.sh

# 一键在线运行
bash <(curl -q -fsSL "https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/run.sh?$(date +%s)")

# 全局安装
curl -q -fsSL "https://raw.githubusercontent.com/sunnyhmz7010/ServerHarbor/main/install.sh?$(date +%s)" | sudo bash

# 交互运行
./menu.sh

# 搜索
rg "pattern" .
```

### 代码组织

- 一个业务领域一个文件，保持扁平目录结构
- 共享函数和默认值放 `common.sh`，节点管理放 `nodes.sh`
- 每个函数必须有对应的菜单或 CLI 入口；无入口即死代码，必须删除
- 不添加菜单 UI 未体现的功能；菜单移除功能时同步删除实现
- `install.sh` 和 `run.sh` 是独立入口脚本，与 `menu.sh` 的代码重复是架构允许的，不要试图合并到 `common.sh`
- `ng_security_report()` 不得重复各扫描函数的逻辑，复用现有助手函数保持 DRY

### 编码风格

- 有副作用的函数优先可读性，避免密集单行写法
- 注释仅在逻辑不明显处添加
- 脚本默认使用 ASCII，除非文件已需要非 ASCII 内容
- README 和菜单描述必须与实际功能完全一致

## Shell 移植性经验

### 管道 stdin（`curl | bash`）

- 管道执行时 stdin 是管道而非终端，所有 `read` 必须用 `read ... < /dev/tty`
- `/dev/tty` 不可用时回退到合理默认值

### `set -e` 与退出码捕获

- 捕获子进程退出码用 `child; code=$?` 配合 `set +e`，或 `child || code=$?`
- `set -e` 下 `if ! child; then code=$?` 仍可能触发退出

### `exec` 与进程替换

- `bash <(curl ...)` 执行时 `$0` 是临时 fd，`exec bash "$0"` 会在 fd 关闭后失败
- 正确做法：先下载到临时文件，再 `exec bash "${tmpfile}"`

### 管道子 shell 变量作用域

- 管道右侧 `while read` 循环中的变量修改会在子 shell 结束后丢失
- 错误：`cat file | while read -r line; do ((count++)); done`
- 正确：`while read -r line; do ((count++)); done < file`

### echo vs printf

- 变量可能含 `-n`、`-e`、`\t` 等转义时，用 `printf '%s\n'` 替代 `echo`
- 简单子串检查优先用 `[[ "${var}" == *"pattern"* ]]`，避免管道

### grep 兼容性

- 禁用 `grep -P`（PCRE），并非所有发行版支持
- 使用 `grep -E`（扩展正则）或 `grep -F`（固定字符串）
- 解析 CPU/内存优先读 `/proc/stat`、`/proc/meminfo`，避免 `top`/`vmstat` 输出格式不一致

## 版本历史

### v1.0.0 (2026-06-26)

- 初始发布
- 系统初始化（基础包、Docker、网络调优）
- 安全审计（登录统计、Web 攻击、防火墙、完整性基线、安全评分）
- 节点管理（TSV 配置、SSH、批量命令、配置同步、互信、远程执行）
- 交互式双语菜单（中文/英文）
- CLI 模式：`--cron-probe`、`--cron-security`、`--cron-alerts`
- 安装/卸载脚本，在线运行模式
- 系统告警阈值检测（CPU/内存/磁盘）
- 批量操作节点选择
- 分节美化报告
- 单配置文件（`serverharbor.conf`）+ TSV 节点块
- 零 jq 依赖（纯 bash + grep/awk/sed）
