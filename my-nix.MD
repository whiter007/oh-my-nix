# my-nix.sh — 一键部署 Nix 脚本

## 概述

`my-nix.sh` 是一个自动安装和配置 Nix 的部署脚本，覆盖所有常见场景。你只需要**克隆仓库，然后执行 `./my-nix.sh`**，脚本会自动检测环境并完成一切。

## 支持的场景矩阵

| 操作系统 | 场景 | Nix 状态 | 执行身份 |
|---------|------|---------|---------|
| **NixOS** | 已安装系统 | 内置 | root / sudo / 普通用户 |
| **NixOS LiveCD** | 全新安装 | 内置 | root（LiveCD 默认） |
| **Linux**（Debian/Ubuntu/Fedora/Arch...） | 未安装 | 无 | root / sudo / 普通用户 |
| **Linux** | 已安装 | 单用户 / 多用户 | root / sudo / 普通用户 |
| **macOS** | 未安装 | 无 | 普通用户 |
| **macOS** | 已安装 | 多用户 | root / sudo / 普通用户 |

> 共覆盖 `4 系统 × 4 安装状态 × 3 执行身份 = 48 种组合`

## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/your-repo/oh-my-nix.git
cd oh-my-nix

# 2. 执行脚本（根据你的系统选择执行方式）

# NixOS LiveCD（全新安装）
./my-nix.sh

# NixOS 已安装系统
sudo ./my-nix.sh

# 通用 Linux（首次安装）
./my-nix.sh                        # 会询问单用户还是多用户安装

# 通用 Linux（已有 Nix）
./my-nix.sh

# macOS
./my-nix.sh
```

## 工作流程

脚本分为三个阶段，五个步骤自动执行：

```
Phase 0 ─── 系统检测
  ├─ 操作系统类型（NixOS / Linux / Darwin）
  ├─ CPU 架构（x86_64 / aarch64，含 Rosetta 处理）
  ├─ LiveCD 检测（3 层兜底）
  ├─ 用户上下文（root / sudo / 普通）
  ├─ Nix 安装状态（内置 / 多用户 / 单用户 / 未安装）
  └─ 硬件信息（CPU 厂商、GPU 列表、IOMMU、KVM）

Phase 1 ─── 安装前置工具 + Nix
  ├─ 安装前置软件（OS 特定）→ Router 分发
  ├─ 安装 Nix（交叉关注点）→ 按 NIX_STATUS 分发
  └─ 配置 Nix（交叉关注点）→ 按 NIX_STATUS 分发

Phase 2 ─── 配置 Nix
  ├─ 写入 nix.conf（国内镜像源、flakes 启用）
  ├─ 添加 nixbld 组（多用户）
  ├─ 重启 nix-daemon（多用户）
  └─ 修复缓存权限

Phase 3 ─── 部署 Flake
  ├─ 磁盘分区（NixOS LiveCD only）→ Router 分发
  ├─ 复制 flake 文件（OS 特定）→ Router 分发
  └─ 应用 flake 配置（OS 特定）→ Router 分发
```

## 架构设计

### Router 模式（类后端 Controller）

```
                  os_handler("phase_name")
                        │
                        ▼
              os_${S_OS_TYPE}_${phase}()
                        │
          ┌─────────────┼─────────────┐
          ▼             ▼             ▼
    os/nixos.sh    os/linux.sh   os/darwin.sh
```

核心路由器 `os_handler()` 定义在 `lib/common.sh`，只有 6 行代码：

```bash
os_handler() {
    local phase="$1"; shift
    local func="os_${S_OS_TYPE}_${phase}"
    if declare -f "$func" >/dev/null 2>&1; then
        "$func" "$@"
    else
        say "Phase '$phase': no handler for os=$S_OS_TYPE (skipped)"
    fi
}
```

### 两条独立的 dispatch 轴

```
OS 轴 (nixos / linux / darwin)
  → os_handler() → os/*.sh
  → 每条执行路径独立，互不干扰

Nix 状态轴 (builtin / multi-installed / single-installed / not-installed)
  → nix.sh 内部按 S_NIX_STATUS 分发
  → 与 OS 轴完全解耦
```

### 文件结构

```
oh-my-nix/
├── my-nix.sh              # 入口脚本（36 行）
├── lib/
│   ├── common.sh          # 常量、日志、路由器、权限助手
│   ├── detect.sh          # 系统/用户/Nix/硬件 检测
│   ├── nix.sh             # Nix 安装和配置（按 NIX_STATUS 分发）
│   └── os/
│       ├── nixos.sh       # NixOS 处理器
│       ├── linux.sh       # 通用 Linux 处理器
│       └── darwin.sh      # macOS 处理器
├── flake.nix              # Flake 配置
├── config/                # Nix 配置文件
├── nixos-modules/         # NixOS 模块
├── home-modules/          # Home Manager 模块
│
│  以下为旧版脚本（参考用，不再维护）
├── oh-my-nix.sh           # 原始完整版
├── glm-my-nix.sh          # 最简洁版
├── yeah-my-nix.sh         # 进度封装版
└── next-my-nix.sh         # 硬件检测版
```

### 职责单一

每个文件只做一件事：

| 文件 | 职责 | 行数 |
|------|------|------|
| `my-nix.sh` | 入口，按顺序调用各阶段 | 36 |
| `lib/common.sh` | 常量定义、日志输出、权限提升/降级、路由分发 | 132 |
| `lib/detect.sh` | 系统信息检测，填充全局状态变量 | 303 |
| `lib/nix.sh` | Nix 安装、配置、注册表、缓存修复（按 `S_NIX_STATUS` 分发） | 225 |
| `lib/os/nixos.sh` | NixOS 各阶段处理器 | 117 |
| `lib/os/linux.sh` | 通用 Linux 各阶段处理器 | 86 |
| `lib/os/darwin.sh` | macOS 各阶段处理器 | 47 |

## 各阶段详细说明

### Phase 0：系统检测

所有检测结果存入 `S_*` 全局变量。检测完成后打印摘要：

```
[info] === System Information ===
[info] OS Type:       linux
[info] Architecture:  x86_64-linux
[info] CPU Vendor:    intel (x86_64)
[info] Live CD:       false
[info] Hostname:      my-pc
[info] User:          whiter (home: /home/whiter)
[info] Root:          false
[info] Sudo:          false
[info] Nix Status:    not-installed
[info] KVM:           true
[info] IOMMU:         true
[info] =========================
```

#### 操作系统检测
- 通过 `uname -s` / `uname -m` 检测
- macOS 处理 Rosetta 2 兼容层（x86_64 下检测真实 arm64）
- NixOS 通过 `/etc/os-release` 中的 `ID=nixos` 来识别
- LiveCD 用 3 层兜底检测（内核命令行 → 只读挂载 → tmpfs overlay）

#### 用户上下文检测
- **普通用户执行**：`S_USER_NAME=whoami`, `S_IS_ROOT=false`
- **sudo 执行**：`S_USER_NAME=$SUDO_USER`, `S_IS_SUDO=true`
- **root 执行**：查找第一个普通用户（`logname` → `awk /etc/passwd`）
- **LiveCD 环境**：提示输入用户名
- **多用户系统 + root 执行**：列出用户菜单供选择

### Phase 1：安装前置工具

#### NixOS
使用 `nix profile add` 安装 git 和 pciutils（不需要系统包管理器）：
```bash
nix profile add nixpkgs#git
nix profile add nixpkgs#pciutils
```

#### 通用 Linux
按优先级自动检测 7 种包管理器，批量安装缺失工具（curl, xz, git, pciutils）：

```
优先级：oma → apt → dnf → yum → pacman → zypper → apk
```

特性：apt/oma 自动将 `xz` 映射为 `xz-utils`；oma 提示执行 `oma mirror`。

#### macOS
检查 git 和 curl 是否存在，lspci 缺失仅警告不中断。

### Phase 1-2：安装和配置 Nix

这是**跨 OS 的关注点**，由 `lib/nix.sh` 统一处理，按 `S_NIX_STATUS` 分发。

#### 安装

| Nix 状态 | 策略 |
|-----------|------|
| `builtin` | NixOS 内置，跳过 |
| `multi-installed` | 已安装，加载环境变量 |
| `single-installed` | 已安装，如果是特权执行则降级重跑 |
| `not-installed` | 根据用户身份决定安装类型 |

安装类型选择逻辑：
- **root/sudo 用户**：默认多用户安装，不询问
- **普通用户**：询问 `1. 单用户 2. 多用户`
- **单用户安装**：如果是 root/sudo 执行，自动 `exec` 降级为普通用户重跑

安装使用清华 tuna 镜像：
```bash
curl -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install | bash
```

#### 配置

| Nix 状态 | nix.conf 路径 | 额外操作 |
|-----------|--------------|---------|
| `builtin` | flake 管理（nix-settings.nix） | 添加 nixbld 组，清理冲突配置 |
| `multi-installed` | `/etc/nix/nix.conf` | 添加 nixbld 组，重启 nix-daemon，验证连通性 |
| `single-installed` | `~/.config/nix/nix.conf` | 无 |

nix.conf 内容（使用国内镜像源）：
```
experimental-features = nix-command flakes
substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store ...
trusted-substituters = ...
trusted-public-keys = ...
builders-use-substitutes = true
auto-optimise-store = true
sandbox-fallback = false
trusted-users = root <username>    # 仅多用户
```

多用户安装的 daemon 验证流程：
1. `systemctl daemon-reload`
2. `systemctl restart nix-daemon.service`
3. 轮询等待 daemon 变为 active（最长 30 秒）
4. `nix store ping` 验证 daemon 正常响应
5. 删除 `/root/.config/nix/nix.conf` 和 `~/.config/nix/nix.conf` 防止冲突

### Phase 3：部署 Flake 配置

#### NixOS

| 场景 | flake 目标路径 | 应用命令 |
|------|--------------|---------|
| LiveCD 全新安装 | `/etc/nixos/` | `nixos-install --flake /etc/nixos/#<hostname>` |
| 已安装系统 | `/etc/nixos/` | `nixos-rebuild switch --flake /etc/nixos/` |

LiveCD 额外步骤：
1. 交互式选择目标磁盘
2. 运行 Disko 分区格式化
3. `nixos-generate-config` 生成硬件配置

#### 通用 Linux

| 项目 | 值 |
|------|-----|
| flake 目标路径 | `~/.config/home-manager/` |
| 应用命令 | `nix run nixpkgs#home-manager -- switch --flake ~/.config/home-manager` |
| 备份策略 | `-b backup`（自动备份旧配置） |

#### macOS

| 项目 | 值 |
|------|-----|
| flake 目标路径 | `~/.config/nix-darwin/` |
| 应用命令 | `nix run nix-darwin -- switch --flake ~/.config/nix-darwin` |

## 权限模型

整个脚本只有两个权限助手函数，所有代码都使用它们——**没有任何地方直接调用 `sudo`**：

### `run_as_root()` — 以 root 身份执行
```bash
# 内部逻辑：已 root → 直接执行；非 root → sudo 提权
# 始终传递 USER/HOME/NIX_CONFIG/PATH 防止环境变量丢失
run_as_root systemctl restart nix-daemon.service
```

### `run_as_user()` — 以目标普通用户身份执行
```bash
# 内部逻辑：已普通 → 直接执行；root/sudo → sudo -u <user> 切换
# 用于 Nix 命令，防止 $HOME 所有权问题
run_as_user nix run nixpkgs#home-manager -- switch ...
```

### `downgrade_privilege()` — 降级重执行
```bash
# 单用户 Nix 安装要求普通用户身份，root/sudo 执行时自动降级：
# exec sudo -u <user> -E HOME=<home> bash "$0" "$@"
```

### 权限覆盖矩阵

| 操作 | NixOS | Linux (multi) | Linux (single) | Darwin |
|------|-------|---------------|----------------|--------|
| 安装前置工具 | `run_as_root` | `run_as_root` | N/A | N/A |
| 安装 Nix | N/A | `run_as_root` | `run_as_user` | `run_as_root` |
| 写 nix.conf | flake | `run_as_root` | `run_as_user` | `run_as_root` |
| nixbld 组 | `run_as_root` | `run_as_root` | N/A | N/A |
| daemon 管理 | N/A | `run_as_root` | N/A | N/A |
| 加 nixpkgs 注册表 | `run_as_user` + `run_as_root` | `run_as_user` + `run_as_root` | `run_as_user` | `run_as_user` |
| 复制 flake | `run_as_root` | `run_as_user` | `run_as_user` | `run_as_user` |
| 应用 flake | `run_as_root` | `run_as_user` | `run_as_user` | `run_as_user` |

## 状态变量参考

所有状态变量以 `S_` 为前缀，由 `detect_all()` 一次性填充，后续只读：

| 变量 | 类型 | 可能的值 | 说明 |
|------|------|---------|------|
| `S_OS_TYPE` | 字符串 | `nixos` / `linux` / `darwin` | 操作系统类型 |
| `S_ARCH` | 字符串 | `x86_64-linux` / `aarch64-darwin` 等 | 系统架构 |
| `S_IS_LIVE_CD` | 布尔 | `true` / `false` | 是否为 NixOS LiveCD |
| `S_USER_NAME` | 字符串 | 用户名 | 目标普通用户（永远不会是 root） |
| `S_USER_HOME` | 字符串 | `/home/xxx` 或 `/Users/xxx` | 用户家目录 |
| `S_IS_ROOT` | 布尔 | `true` / `false` | 是否 root 直接执行 |
| `S_IS_SUDO` | 布尔 | `true` / `false` | 是否通过 sudo 执行 |
| `S_NIX_STATUS` | 字符串 | `builtin` / `multi-installed` / `single-installed` / `not-installed` | Nix 安装状态 |
| `S_HOST_NAME` | 字符串 | 主机名 | 用于 nixosConfigurations 的 key |
| `S_CPU_VENDOR` | 字符串 | `intel` / `amd` / `unknown` | CPU 厂商 |
| `S_CPU_ARCH` | 字符串 | `aarch64` / `x86_64` | CPU 指令集架构 |
| `S_HAS_IOMMU` | 布尔 | `true` / `false` | 是否支持 IOMMU |
| `S_HAS_KVM` | 布尔 | `true` / `false` | 是否支持 KVM 虚拟化 |

## 扩展：添加新系统支持

只要 3 步，不需要修改任何已有文件：

**1.** 创建 `lib/os/freebsd.sh`
```bash
#!/bin/bash
os_freebsd_install_prereqs() {
    say "Checking FreeBSD prerequisites..."
    check_cmd git || run_as_root pkg install -y git
    # ...
}
os_freebsd_load_flake() { ... }
os_freebsd_apply_flake() { ... }
os_freebsd_celebrate() { ... }
```

**2.** 在 `my-nix.sh` 添加一行 source
```bash
source "$SCRIPT_DIR/lib/os/freebsd.sh"
```

**3.** 如果 `uname -s` 返回的操作系统名称需要特殊处理，在 `lib/detect.sh` 的 `_detect_os_arch()` 中增加对应的 case。

**完成。** 路由器 `os_handler()` 会自动将 FreeBSD 的各阶段请求分发给对应的函数。如果某个阶段不需要（如 `setup_disks`），不定义该函数即可自动跳过。

## 与旧版脚本的对比

| 方面 | 旧版（oh-my-nix.sh 等） | 新版（my-nix.sh） |
|------|----------------------|-------------------|
| **架构** | 每个函数内 `case $OS_TYPE` 分发 | Router 模式，OS 处理器分离 |
| **SOLID** | 违反 — 一个函数适配多种 OS | 遵守 — 每个函数单一职责 |
| **修改成本** | 改一个 OS 逻辑需要翻 700+ 行 | 只改对应的 `os/*.sh` |
| **添加系统** | 修改 10+ 个函数 | 新建 1 个文件 + 1 行 source |
| **权限** | `use_sudo` / `use_normal` / 直接 sudo 混用 | 统一 `run_as_root` / `run_as_user` |
| **文件数** | 4 个独立脚本（~2300 行总计） | 1 入口 + 6 模块（~950 行总计） |
| **输出风格** | 各版本不一致 | 统一 glm-my-nix 彩色风格 |

## 常见问题

### Q: 在已有 Nix 的 Linux 上运行会怎样？
脚本检测到 Nix 已安装后跳过安装步骤，直接进入配置（更新 nix.conf 使用国内源）和应用 flake。

### Q: root 执行单用户安装会怎样？
脚本会自动 `exec sudo -u <user>` 降级为普通用户重新执行，确保单用户安装的 `$HOME/.nix-profile` 目录所有权正确。

### Q: LiveCD 上需要手动分区吗？
不需要。脚本会交互式列出所有磁盘供你选择，然后自动运行 Disko 完成分区格式化。

### Q: 支持 WSL 吗？
WSL 被视为通用 Linux，走 Linux 处理路径。lspci 输出格式已在 `_normalize_pci_bus_id()` 中兼容处理。

### Q: Flake 应用失败怎么办？
`home-manager switch -b backup` 会自动备份旧配置。NixOS 的 `nixos-rebuild switch` 支持回滚（`nixos-rebuild switch --rollback`）。

### Q: 如何只检测而不执行后续操作？
目前脚本是全自动的。如需分步执行，可以查看 `my-nix.sh` 的 `main()` 函数了解各步骤，然后注释掉不需要的阶段手动执行。
