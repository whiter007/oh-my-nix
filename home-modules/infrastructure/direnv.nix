{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    direnv # direnv
  ];
}
