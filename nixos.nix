# 用户编辑的主入口文件
{ config, pkgs, lib, username, myNixosVersion, ... }:

let
  modulesPath = ./nixos-modules;
in
{
  imports =
    [
      ./hardware-configuration.nix
      # ${modulesPath}/controller/addon-config.nix
      (modulesPath + /controller/desktop-config.nix)
      (modulesPath + /controller/hardware-config.nix)
      (modulesPath + /controller/system-config.nix)
      (modulesPath + /controller/user-config.nix)
    ];

  # 用户可配置的选项
  my = {
    # 桌面环境选择
    desktop = {
      type = "hyprland"; # hyprland | gnome(default) | minimal | none
      displayServer = "wayland"; # x11(default) or wayland
    };
    # 硬件配置
    hardware = {
      cpu = {
        brand = "intel"; # default | intel | amd
        performance = "balanced"; # balanced | power-saving | performance
      };
      gpu = "nvidia"; # default(nouveau) | nvidia | amd | intel
      virtualization = {
        enable = false;
        type = "docker"; # docker(default) | podman | libvirt
        usemirrors = true; # true if in china
      };
      enableBluetooth = true;
    };
    # 系统配置
    system = {
      state-version = "25.11";
      boot.type = "grub"; # grub | systemd
      hostname = "nixos";
      timezone = "Asia/Shanghai";
      local-language = "zh_CN.UTF-8";
      kernel = "default"; # default(latest) | lts | zen | hardened
    };
    # 用户配置
    user = {
      name = "alice";
      email = "alice@example.com";
      theme = {
        enable = false;
        name = "catppuccin-mocha";
        variant = "dark";
      };
    };
  };

  system.stateVersion = "${myNixosVersion}";
}
