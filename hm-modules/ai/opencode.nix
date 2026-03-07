# https://github.com/anomalyco/opencode
{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    opencode
  ];

  # ========== 创建 OpenCode wrapper 脚本 ==========
  home.file.".config/opencode/opencode-wrapper".text = ''
    #!/bin/bash
    # 设置 OpenCode 环境变量
    if [ -f "$HOME/.config/home-manager/secrets.env" ]; then
      set -a  # 自动 export 所有变量
      . "$HOME/.config/home-manager/secrets.env"
      set +a  # 关闭自动 export
    fi
    # 执行原始 opencode 命令
    exec opencode "$@"
  '';
  home.file.".config/opencode/opencode-wrapper".executable = true;
}
