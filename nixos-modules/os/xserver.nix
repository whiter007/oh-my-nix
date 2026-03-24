{ config, pkgs, lib, inputs, ... }:

{
  # 启用X11窗口管理系统
  services.xserver.enable = true;
}