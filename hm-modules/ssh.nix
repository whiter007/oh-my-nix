{ config, pkgs, lib, ... }:

{
  # ========== SSH客户端全局配置（可选，保留你原来的需求） ==========
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false; # ✅ 禁用默认配置以避免警告
    # ✅ 使用 matchBlocks."*" 替代 extraConfig
    matchBlocks."github.com" = {
      hostname = "ssh.github.com";
      port = 443;
      user = "git";
    };
    matchBlocks."*" = {
      extraOptions = {
        StrictHostKeyChecking = "no";
        UserKnownHostsFile = "/dev/null";
        LogLevel = "INFO";
      };
    };
  };
  # ========== 自动生成SSH密钥 ==========
  # ✅ 使用绝对路径调用 ssh-keygen，不依赖 PATH
  # ✅ 幂等操作：如果密钥已存在则跳过，不会重复生成
  home.activation.generateSshKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p $HOME/.ssh
    chmod 0700 $HOME/.ssh

    # SSH_KEYGEN="${pkgs.openssh}/bin/ssh-keygen"

    if [ ! -f $HOME/.ssh/id_ed25519 ]; then
      echo "🔑 未检测到SSH密钥，正在自动生成无密码的Ed25519密钥..."
      ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f $HOME/.ssh/id_ed25519 -N "" -C "whiter007@qq.com" -q
      # 生成后立即设置正确的权限
      chmod 0600 $HOME/.ssh/id_ed25519
      chmod 0644 $HOME/.ssh/id_ed25519.pub
    else
      # 密钥已存在，只确保权限正确（幂等操作）
      chmod 0600 $HOME/.ssh/id_ed25519 2>/dev/null || true
      chmod 0644 $HOME/.ssh/id_ed25519.pub 2>/dev/null || true
    fi
    echo "✅ SSH密钥配置完成！"
    echo "📋 请复制以下公钥添加到GitHub："
    echo "----------------------------------------"
    cat $HOME/.ssh/id_ed25519.pub
    echo "----------------------------------------"
    echo "💡 测试连接命令：ssh -T -p 443 git@ssh.github.com"
    echo "💡 测试连接命令：ssh -T git@github.com"
  ''; # ========== SSH相关软件包 ==========
  home.packages = with pkgs; [
    openssh # 全套ssh工具：ssh-keygen/ssh/scp/ssh-add
  ];
}
