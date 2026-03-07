{ config, lib, ... }:

let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.my.system = {
    state-version = mkOption {
      type = types.str;
      default = "25.11";
      description = "NixOS state version";
    };

    boot = {
      type = mkOption {
        type = types.enum [ "grub" "systemd" ];
        default = "grub";
        description = "Boot loader type: grub | systemd";
      };
    };

    hostname = mkOption {
      type = types.str;
      default = "nixos";
      description = "System hostname";
    };

    timezone = mkOption {
      type = types.str;
      default = "Asia/Shanghai";
      description = "System timezone";
    };

    local-language = mkOption {
      type = types.str;
      default = "zh_CN.UTF-8";
      description = "System locale";
    };

    kernel = mkOption {
      type = types.enum [ "default" "lts" "zen" "hardened" ];
      default = "default";
      description = "Kernel type: default(latest) | lts | zen | hardened";
    };
  };
}
