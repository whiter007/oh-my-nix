{ config, pkgs, lib, inputs, ... }:

{
  imports =
    [
      # 1. 引导配置
      ./boot.nix # 引导配置
      # 2. 网络配置
      ./networking.nix # 网络配置
      # 3. 时区配置
      ./time.nix # 时区配置
      # 4. 国际化配置
      ./i18n.nix # 国际化配置
      # 5. xserver 配置
      ./xserver.nix # xserver 配置
      # 6. 声音配置
      ./sound.nix # 声音配置
      # 7. 安全配置
      # ./security.nix # 安全配置
      # 8. 用户配置
      ./user.nix # 用户配置
    ];
}
