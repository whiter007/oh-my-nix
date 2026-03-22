# 项目介绍
一键还原您的nix单机配置
让脚本适应您的环境

# 项目功能

| 特性 | NixOS | Linux | MacOS |
| --- | --- | --- | --- |
| 分区 | ✅ | —— | —— |
| 安装前置软件 | ✅ | ✅ | ❌ |
| 单安装nix安装 | —— | ✅ | ❌ |
| 多用户nix安装 | —— | ✅ | ❌ |
| 配置nix | ✅ | ✅ | ❌ |
| CPU检测 | ❌ | ❌ | ❌ |
| GPU检测 | ❌ | ❌ | ❌ |
| 虚拟化检测 | ❌ | ❌ | ❌ |
| 生成硬件配置 | ❌ | ❌ | ❌ |
| 应用flake配置 | ✅ | ✅ | ❌ |



# 脚本执行方式
| 脚本执行方式 | NixOS | NixOS live cd | Linux | MacOS |
| --- | --- | --- | --- | --- |
| 普通用户执行 | ✅ | —— | ✅ | ❌ |
| sudo用户执行 | ✅ | —— | ✅ | ❌ |
| root用户执行 | ✅ | ❌ | ✅ | ❌ |


# 快速使用
```bash
git clone https://github.com/whiter007/oh-my-nix.git
cd oh-my-nix/
bash oh-my-nix.sh
```

# TODO
1. 解决以root或sudo用户执行oh-my-nix.sh脚本的问题
2. 解决在nixos的live cd下执行oh-my-nix.sh脚本的问题
