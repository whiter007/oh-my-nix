# https://github.com/Aider-AI/aider
{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    aider-chat
  ];

  # ========== 创建 Aider wrapper 脚本 ==========
  home.file.".config/aider/aider-wrapper".text = ''
    #!/bin/bash
    # 设置 Aider 环境变量
    if [ -f "$HOME/.config/home-manager/secrets.env" ]; then
      set -a  # 自动 export 所有变量
      . "$HOME/.config/home-manager/secrets.env"
      set +a  # 关闭自动 export
    fi
    # 执行原始 aider 命令
    exec aider "$@"
  '';
  home.file.".config/aider/aider-wrapper".executable = true;
}
