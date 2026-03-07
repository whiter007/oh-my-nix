{ config, lib, ... }:

let
  # 导入domain选项
  desktopOptions = import ../domain/options/desktop.nix;
  hardwareOptions = import ../domain/options/hardware.nix;
  userOptions = import ../domain/options/user.nix;
in
{
  imports = [
    desktopOptions
    hardwareOptions
    userOptions

    # 根据选择导入对应的use-case配置
    ../use-case/desktop/gnome.nix
    ../use-case/desktop/hyprland.nix
    ../use-case/desktop/minimal.nix

    ../use-case/hardware/nvidia.nix
    ../use-case/hardware/amd.nix
    ../use-case/hardware/intel.nix

    ../use-case/system/base.nix
  ];

  # 根据选项自动启用/禁用特性
  config = {
    # 自动设置显卡相关服务
    services.xserver.enable =
      config.my.desktop.type != "none" && config.my.desktop.enableX11;

    # Wayland自动配置
    services.xserver.displayManager.defaultSession =
      if config.my.desktop.type == "hyprland" then "hyprland"
      else if config.my.desktop.type == "gnome" && config.my.desktop.enableWayland
      then "gnome-wayland"
      else "gnome-xorg";

    # 性能调优
    powerManagement.cpuFreqGovernor =
      if config.my.hardware.cpu.performance == "power-saving" then "powersave"
      else if config.my.hardware.cpu.performance == "performance" then "performance"
      else "ondemand";
  };
}
