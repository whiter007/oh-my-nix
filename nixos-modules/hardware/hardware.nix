{ config, pkgs, ... }:

{
  # 允许非自由固件（网卡/声卡/WiFi 必备）
  nixpkgs.config.allowUnfree = true;

  # 启用所有通用固件（一键解决绝大多数外设不认）
  hardware.enableAllFirmware = true;

  # 显卡/3D 加速（Intel/AMD/NVIDIA 通用）
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };

  # 音频
  sound.enable = true;
  hardware.pulseaware.enable = true; # 普通够用
  # 想用新版 pipewire 就替换成下面：
  # hardware.pipewire.enable = true;
  # hardware.pipewire.alsa.enable = true;
  # hardware.pipewire.pulse.enable = true;

  # USB / 外设权限
  services.udev.packages = [
    pkgs.libusb-compat-0.1
    pkgs.usbutils
  ];

  # 移动硬盘/U盘 支持
  boot.supportedFilesystems = [ "vfat" "ntfs" "exfat" ];

  # 蓝牙（需要就开）
  # hardware.bluetooth.enable = true;

  # 打印机（需要就开）
  # services.printing.enable = true;
}