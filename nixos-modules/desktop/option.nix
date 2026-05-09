{ config, pkgs, lib, inputs, ... }:
let
  thisConfig = config.my.desktop;
  inherit (lib) mkEnableOption mkOption types mkMerge mkIf;
in
{
  # 1. 标准启用选项
  options.my.desktop = {
    enable = mkEnableOption "是否启用自定义桌面环境配置";

    type = mkOption {
      type = types.enum [ "gnome" "hyprland" "niri" "dms"];
      default = "gnome";
      description = "选择桌面环境：gnome/hyprland/niri/dms，默认gnome";
    };
  };


  # 2. imports 必须写在最外层，用 mkIf 条件导入
  imports = [
    # GNOME
    (mkIf (thisConfig.enable && thisConfig.type == "gnome")
      ./gnome/gnome.nix)

    # Hyprland
    (mkIf (thisConfig.enable && thisConfig.type == "hyprland")
      ./hyprland/hyprland.nix)
  ];


  # 2. 其他配置
  config = mkIf thisConfig.enable (mkMerge [
    # GNOME
    (mkIf (thisConfig.type == "gnome") {
    })

    # Hyprland
    (mkIf (thisConfig.type == "hyprland") {
    })

    # Niri
    (mkIf (thisConfig.type == "niri") {
    })

    # DMS
    (mkIf (thisConfig.type == "dms") {
    })
  ]);
}