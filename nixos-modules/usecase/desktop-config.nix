{ config, lib, pkgs, ... }:

let
  # 根据显卡类型选择 Wayland 或 X11
  useWayland = config.my.gpu != "nvidia" || config.my.nvidia.wayland;
in
{
  config = lib.mkMerge [
    # GNOME 配置
    (lib.mkIf (config.my.desktop == "gnome") {
      services.xserver = {
        enable = true;
        displayManager.gdm = {
          enable = true;
          wayland = useWayland;
        };
        desktopManager.gnome.enable = true;
      };

      # GNOME 扩展
      environment.systemPackages = with pkgs; [
        gnomeExtensions.dash-to-dock
        gnomeExtensions.arc-menu
      ];

      # 优化配置
      services.gnome.games.enable = false;
      environment.gnome.excludePackages = with pkgs; [
        gnome.cheese
        gnome.epiphany
      ];
    })

    # Hyprland 配置
    (lib.mkIf (config.my.desktop == "hyprland") {
      programs.hyprland = {
        enable = true;
        xwayland.enable = true;
        nvidiaPatches = config.my.gpu == "nvidia";
      };

      # 显示管理器
      services.xserver.displayManager.sddm = {
        enable = true;
        wayland.enable = true;
      };

      # 必要组件
      environment.systemPackages = with pkgs; [
        waybar
        rofi-wayland
        swaybg
        swaylock-effects
      ];

      # 环境变量
      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        QT_QPA_PLATFORM = "wayland";
        SDL_VIDEODRIVER = "wayland";
        CLUTTER_BACKEND = "wayland";
      };
    })
  ];
}
