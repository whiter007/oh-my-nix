{ config, lib, ... }:

let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.my.desktop = {
    type = mkOption {
      type = types.enum [ "hyprland" "gnome" "minimal" "none" ];
      default = "gnome";
      description = "Desktop environment to use: hyprland | gnome(default) | minimal | none";
    };

    displayServer = mkOption {
      type = types.enum [ "x11" "wayland" ];
      default = "x11";
      description = "Display server to use: x11(default) or wayland";
    };
  };
}
