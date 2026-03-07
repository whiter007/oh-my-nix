{ ... }:

{
  # X11 键盘配置
  services.xserver.xkb = {
    layout = "cn"; # 设置键盘布局为中文（中国）
    variant = ""; # 键盘变体，空字符串表示使用标准布局
  }

    # 启用触摸板支持（在大多数桌面管理器中默认启用）
    # services.xserver.libinput.enable = true;
}
