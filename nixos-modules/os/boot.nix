{ config, pkgs, lib, inputs, ... }:

{
  # 使用 GRUB 2 引导加载器
  boot.loader = {
    # efi.efiSysMountPoint = "/boot/efi";
    grub = {
        enable = true;
        # efiSupport = true;
        # efiInstallAsRemovable = true;
        # 声明你想在哪个硬盘安装 Grub
        device = "/dev/sda"; # 或者 "nodev" 以只使用efi引导 (必须设置)
    };
  };
}
