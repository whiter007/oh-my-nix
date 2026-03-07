{ config, lib, ... }:

let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.my.hardware = {
    cpu = {
      brand = mkOption {
        type = types.enum [ "default" "intel" "amd" ];
        default = "default";
        description = "CPU brand: default | intel | amd";
      };

      performance = mkOption {
        type = types.enum [ "balanced" "power-saving" "performance" ];
        default = "balanced";
        description = "CPU performance profile: balanced | power-saving | performance";
      };
    };

    gpu = mkOption {
      type = types.enum [ "default" "nvidia" "amd" "intel" ];
      default = "default";
      description = "GPU type: default(nouveau) | nvidia | amd | intel";
    };

    enableBluetooth = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Bluetooth support";
    };

    enableVirtualization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable virtualization support";
    };
    virtualization = {
      enable = mkEnableOption "Virtualization support";
      type = mkOption {
        type = types.enum [ "docker" "podman" "libvirt" ];
        default = "docker";
        description = "Virtualization technology";
      };
    };
  };
}
