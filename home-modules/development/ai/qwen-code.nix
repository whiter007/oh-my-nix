# https://github.com/QwenLM/qwen-code
{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    qwen-code
  ];

  # ========== 创建 Qwen Code wrapper 脚本 ==========
  home.file.".config/qwen-code/qwen-code-wrapper".text = ''
    #!/bin/bash
    # 设置 Qwen Code 环境变量
    if [ -f "$HOME/.config/home-manager/secrets.env" ]; then
      set -a  # 自动 export 所有变量
      . "$HOME/.config/home-manager/secrets.env"
      set +a  # 关闭自动 export
    fi
    # 执行原始 qwen-code 命令
    exec qwen-code "$@"
  '';
  home.file.".config/qwen-code/qwen-code-wrapper".executable = true;
}
