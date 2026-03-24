{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    gemini-cli
  ];

  # ========== 创建 Gemini CLI wrapper 脚本 ==========
  home.file.".config/gemini/gemini-wrapper".text = ''
    #!/bin/bash
    # 设置 Gemini CLI 环境变量
    if [ -f "$HOME/.config/home-manager/secrets.env" ]; then
      set -a  # 自动 export 所有变量
      . "$HOME/.config/home-manager/secrets.env"
      set +a  # 关闭自动 export
    fi
    # 执行原始 gemini 命令
    exec gemini "$@"
  '';
  home.file.".config/gemini/gemini-wrapper".executable = true;
}
