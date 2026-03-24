{ config, pkgs, lib, ... }:

{
  # 终端显示必备
  home.packages = with pkgs; [
    nerd-fonts.fira-code # Nerd Fonts 图标字体，解决 neovim 图标显示问号问题
    nerd-font-patcher
    noto-fonts-color-emoji
  ];

  # 终端显示美化
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true; # 每条命令输出后换行
      aws.disabled = true; # 禁用 Starship 的 AWS 插件，无需AWS credentials提示
      gcloud.disabled = true; # 禁用 Starship 的 gcloud (Google Cloud) 插件，避免无关提示
      line_break.disabled = false; # 禁用多余的换行符插件，使 prompt 更紧凑
    };
  };

  # 终端显示加速
  # programs.alacritty = {
  #   enable = true;
  #   settings = {
  #     env = {
  #       TERM = "xterm-256color";
  #     };
  #     window = {
  #       dimensions = {
  #         columns = 120;
  #         lines = 36;
  #       };
  #     };
  #     # 设置Alacritty的颜色主题
  #     colors = {
  #       primary = {
  #         background = "0x282c34";
  #         foreground = "0xabb2bf";
  #       };
  #       # ...
  #     };
  #   };
  # };
}
