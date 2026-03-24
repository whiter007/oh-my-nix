{ config, pkgs, lib, ... }:

{
  programs.bash = {
    # 一般系统的默认终端
    enable = true;
    enableCompletion = true; # 自动补全功能
    initExtra = ''
      eval "$(direnv hook bash)"

      # 直接导出变量
      # if [ -f "$HOME/.config/home-manager/secrets.env" ]; then
      #   set -a  # 自动 export 所有变量
      #   . "$HOME/.config/home-manager/secrets.env"
      #   set +a  # 关闭自动 export
      # fi

      # Claude Code 别名，使用wrapper脚本启动
      alias claude='~/.config/claude/claude-wrapper'
      # Gemini CLI 别名，使用wrapper脚本启动
      alias gemini='~/.config/gemini/gemini-wrapper'
    '';
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # 使用新的 initContent 替代已弃用的 initExtraBeforeCompInit
    initContent = lib.mkOrder 550 ''
      eval "$(direnv hook zsh)"

      # 直接导出变量
      # if [ -f "$HOME/.config/home-manager/secrets.env" ]; then
      #   set -a  # 自动 export 所有变量
      #   . "$HOME/.config/home-manager/secrets.env"
      #   set +a  # 关闭自动 export
      # fi

      # Claude Code 别名，使用wrapper脚本启动
      alias claude='~/.config/claude/claude-wrapper'
      # Gemini CLI 别名，使用wrapper脚本启动
      alias gemini='~/.config/gemini/gemini-wrapper'
    '';
  };

  programs.nushell = {
    enable = true;
    # nu 配置文件所在目录
    # 默认为 ~/.config/nu/config.nu
    # 这里可以设置为 ~/.config/nu/nu.config
    # 如果文件不存在，则会自动创建
    # config = { source = "${config.home.homeDirectory}/.config/nu/nu.config"; };

    # 使用 Starship 主题
    shellAliases = {
      claude = "~/.config/claude/claude-wrapper";
      gemini = "~/.config/gemini/gemini-wrapper";
    };
  };

  programs.fish = {
    enable = true;
    # fish 配置文件所在目录
    # 默认为 ~/.config/fish/config.fish
    # 这里可以设置为 ~/.config/fish/fish.config
    # 如果文件不存在，则会自动创建
    # config = { source = "${config.home.homeDirectory}/.config/fish/fish.config"; };

    # 使用 Starship 主题
    shellAliases = {
      claude = "~/.config/claude/claude-wrapper";
      gemini = "~/.config/gemini/gemini-wrapper";
    };
  };
}
