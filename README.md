# 项目介绍
一键还原您的nix单机配置
让脚本适应您的环境

# 项目功能实现

| 特性 | NixOS | Linux | MacOS |
| --- | --- | --- | --- |
| 前置软件安装 | ✅ | ✅ | ❌ |
| 单安装nix安装 | —— | ✅ | ❌ |
| 多用户nix安装 | —— | ✅ | ❌ |
| nix配置 | ✅ | ✅ | ❌ |
| CPU检测 | ❌ | ❌ | ❌ |
| GPU检测 | ❌ | ❌ | ❌ |
| 虚拟化检测 | ❌ | ❌ | ❌ |
| 硬盘检测 | ❌ | —— | —— |
| 分区 | ✅ | —— | —— |
| 生成硬件配置 | ❌ | ❌ | ❌ |
| 生成flake配置 | ❌ | ❌ | ❌ |
| 复制flake配置 | ❌ | ❌ | ❌ |
| 应用flake配置 | ✅ | ✅ | ❌ |



# 脚本执行环境
| 脚本执行环境 | 可用性 | 用户名 |
| --- | --- | --- |
| NixOS Live CD 普通用户执行 | ❌ | 自定义 |
| NixOS Live CD sudo用户执行 | ❌ | 自定义 |
| NixOS Live CD root用户执行 | ❌ | 自定义 |
| NixOS 已安装 普通用户执行 | ❌ | 当前用户(USER) |
| NixOS 已安装 sudo用户执行 | ❌ | 当前用户(SUDU_USER) |
| NixOS 已安装 root执行 含单用户 | ❌ | 自动选择 |
| NixOS 已安装 root执行 含多用户 | ❌ | 手动选择 |
| Linux 已安装 普通用户执行 | ❌ | 当前用户(USER) |
| Linux 已安装 sudo用户执行 nix单用户安装 | ❌ | 当前用户(SUDU_USER) |
| Linux 已安装 sudo用户执行 nix多用户安装 | ❌ | 当前用户(SUDU_USER) |
| Linux 已安装 root执行 nix单用户安装 含单用户 | ❌ | 自动选择 |
| Linux 已安装 root执行 nix单用户安装 含多用户 | ❌ | 自动选择 |
| Linux 已安装 root执行 nix多用户安装 含单用户 | ❌ | 自动选择 |
| Linux 已安装 root执行 nix多用户安装 含多用户 | ❌ | 手动选择 |
<!-- | MacOS 已安装 普通用户执行 | ❌ | 当前用户(USER) |
| MacOS 已安装 sudo用户执行 | ❌ | 当前用户(SUDU_USER) |
| MacOS 已安装 root含单用户执行 | ❌ | 自动选择 |
| MacOS 已安装 root含多用户执行 | ❌ | 手动选择 | -->


# 快速使用
```bash
git clone https://github.com/whiter007/oh-my-nix.git
cd oh-my-nix/
bash oh-my-nix.sh
```

# TODO
1. 添加 nixos live cd 的硬盘检测
2. 添加 nixos live cd 的硬盘配置生成
