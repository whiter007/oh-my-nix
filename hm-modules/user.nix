{ config, pkgs, lib, username, myNixosVersion, ... }:

{
  home.username = "${username}"; # ⚠️不要删除这一行
  home.homeDirectory = "/home/${username}"; # ⚠️不要删除这一行
  home.stateVersion = "${myNixosVersion}"; # ⚠️不要删除这一行
  # 启用 home-manager 核心支持
  programs.home-manager.enable = true; # ⚠️不要删除这一行

  # 启用字体配置，支持 Nerd Fonts 图标
  fonts.fontconfig.enable = true;

  # ========== 环境变量配置 ==========
  home.sessionVariables = {
    PATH = "$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"; # ⚠️不要删除这一行
    SSH_CONFIG = "/dev/null"; # 忽略系统SSH配置文件
  };

}
