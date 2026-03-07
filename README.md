# 项目介绍
项目包含一个仅适用于impure模式的oh-my-nix.sh脚本和flake配置
通过执行oh-my-nix.sh脚本，即可完成nix的安装和配置，一键还原您的单机配置

# 快速使用
```bash
git clone https://github.com/whiter007/oh-my-nix.git
cd oh-my-nix/
bash oh-my-nix.sh
```

# 项目期望
1. 能够以root、sudo用户和普通用户下执行
2. 能够在不同系统下运行，包含nixos、linux等等
3. 能够在nixos的live cd下运行
4. 让脚本和配置适应你的设备

# 已实现的
1. 在普通用户下，在nixos或linux下执行oh-my-nix.sh脚本，即可完成nix的安装和配置

# TODO
1. 解决以root或sudo用户执行oh-my-nix.sh脚本的问题
2. 解决在nixos的live cd下执行oh-my-nix.sh脚本的问题
