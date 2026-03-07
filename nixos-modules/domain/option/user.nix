{ config, lib, ... }:

let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.my.user = {
    name = mkOption {
      type = types.str;
      default = "alice";
      description = "User name";
    };

    email = mkOption {
      type = types.str;
      default = "alice@example.com";
      description = "User email";
    };

    theme = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable theme configuration";
      };

      name = mkOption {
        type = types.str;
        default = "catppuccin-mocha";
        description = "Theme name";
      };

      variant = mkOption {
        type = types.enum [ "light" "dark" ];
        default = "dark";
        description = "Theme variant: light | dark";
      };
    };
  };
}
