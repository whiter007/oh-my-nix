{ config, pkgs, lib, inputs, ... }:

{
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true
}