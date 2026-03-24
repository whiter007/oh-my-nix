{ config, pkgs, lib, inputs, ... }:

{
  # 网络配置
  networking = {
    hostName = "nixos"; # 声明您的主机名
    # wireless.enable = true; # 通过wpa_supplicant启用无线网络支持

    # 如果有需要，配置网络代理
    # proxy = {
    #   default = "http://user:password@proxy:port/";
    #   noProxy = "127.0.0.1,localhost,internal.domain";
    # };

    # 启用网络管理器
    networkmanager.enable = true;
  };
}