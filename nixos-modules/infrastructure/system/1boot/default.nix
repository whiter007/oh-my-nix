{ ... }:

{
  # 引导加载程序
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda"; # 引导设备
    useOSProber = true; # 自动检测其他操作系统
  }
}
