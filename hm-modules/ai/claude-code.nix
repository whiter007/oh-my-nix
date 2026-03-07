{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    claude-code
  ];

  # ========== 创建 Claude Code wrapper 脚本 ==========
  home.file.".config/claude/claude-wrapper".text = ''
    #!/bin/bash
    # 设置 Claude Code 环境变量
    export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
    export ANTHROPIC_MODEL="deepseek-chat"
    export ANTHROPIC_SMALL_FAST_MODEL="deepseek-chat"
    if [ -f "$HOME/.config/home-manager/secrets.env" ]; then
      set -a  # 自动 export 所有变量
      . "$HOME/.config/home-manager/secrets.env"
      set +a  # 关闭自动 export
    fi
    # 执行原始 claude 命令
    exec claude "$@"
  '';
  home.file.".config/claude/claude-wrapper".executable = true;

  # ========== 自动配置 Claude Code 配置文件 ==========
  home.activation.checkClaudeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        CONFIG_FILE="${config.home.homeDirectory}/.claude.json"

        # 如果配置文件不存在，创建基础配置
        if [ ! -f "$CONFIG_FILE" ]; then
          echo "🔧 自动创建 Claude Code 配置文件..."
          mkdir -p "$(dirname "$CONFIG_FILE")"
          cat > "$CONFIG_FILE" << 'EOF'
    {
      "hasCompletedOnboarding": true
    }
    EOF
          echo "✅ Claude Code 配置文件已自动创建并配置完成！"
        # 如果配置文件存在但缺少 hasCompletedOnboarding 字段，自动添加
        elif ! grep -q '"hasCompletedOnboarding":\s*true' "$CONFIG_FILE" 2>/dev/null; then
          echo "🔧 自动更新 Claude Code 配置文件..."
          # 使用 jq 处理 JSON，如果不可用则使用 sed
          if command -v jq >/dev/null 2>&1; then
            jq '.hasCompletedOnboarding = true' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
          else
            # 备用方案：简单追加字段（可能不完美但有效）
            if grep -q '{' "$CONFIG_FILE"; then
              sed -i 's/}/,\n  "hasCompletedOnboarding": true\n}/' "$CONFIG_FILE"
            fi
          fi
          echo "✅ Claude Code 配置文件已自动更新！"
        else
          echo "✅ Claude Code 配置文件已存在且配置正确！"
        fi
  '';
}
