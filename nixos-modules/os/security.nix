{ config, pkgs, lib, inputs, ... }:

{
  # 某些程序需要 SUID 包装器，可以进一步配置或在用户会话中启动
  # programs.mtr.enable = true; # 网络诊断工具 mtr 需要 SUID 权限
  # programs.gnupg.agent = { # GPG 代理可能需要特殊权限来访问硬件安全模块
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # 列出你想要启用的服务：

  # 启用 OpenSSH 守护进程
  # services.openssh.enable = true;

  # 在防火墙中开放端口
  # networking.firewall.allowedTcPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts =[...];
  # 或者完全禁用防火墙
  # networking.firewall.enable = false;
}
