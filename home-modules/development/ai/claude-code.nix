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

  # ========== 自定义 Claude Code 斜杠命令 (通过 /command-name 调用) ==========
  home.file.".claude/commands/commit.md".text = ''
    ## commit

    根据当前 git 仓库的变更生成 Conventional Commit。

    ### 步骤
    1. 运行 `git diff` 查看所有变更
    2. 分析变更内容，生成合适的 commit message
    3. 使用 Conventional Commits 格式: `type(scope): description`
    4. 常用 type: feat, fix, chore, docs, style, refactor, perf, test, ci
    5. 运行 `git add` 暂存文件，然后 `git commit` 提交
    6. 提交信息保持简洁，用中文写
  '';

  home.file.".claude/commands/review.md".text = ''
    ## review

    全面审查未提交的代码变更，关注代码质量、安全性和最佳实践。

    ### 审查重点
    - 代码正确性和逻辑完整性
    - 安全漏洞（命令注入、路径遍历、敏感信息泄露等）
    - 性能问题和不必要的复杂度
    - 错误处理和边界情况
    - 过度工程或不必要的抽象

    ### 输出格式
    对每个问题给出：风险等级(高/中/低)、问题描述、修复建议。
  '';

  home.file.".claude/commands/simplify.md".text = ''
    ## simplify

    审查已修改的代码，关注可复用性、质量和效率，然后直接修复发现的问题。

    ### 检查清单
    - 是否有重复代码可以提取复用？
    - 是否有不必要的抽象或过度设计？
    - 是否有可以简化的复杂逻辑？
    - 命名是否清晰表达意图？
    - 是否有死代码或注释掉的代码？
  '';

  home.file.".claude/commands/explain.md".text = ''
    ## explain

    详细解释指定的代码或模块的工作原理。

    ### 说明包括
    - 整体功能和目的
    - 关键设计模式
    - 数据流和执行路径
    - 重要函数/类的作用
    - 改进建议（可选）
  '';

  home.file.".claude/commands/fix.md".text = ''
    ## fix

    诊断并修复代码库中的问题。

    ### 工作流程
    1. 分析错误信息或问题描述
    2. 定位根因
    3. 给出修复方案并实施
    4. 验证修复是否有效
  '';

  home.file.".claude/commands/refactor.md".text = ''
    ## refactor

    重构选中的代码，改善结构和可维护性，不改变外部行为。

    ### 原则
    - 保持功能完全不变
    - 改善代码结构和可读性
    - 提取公共逻辑，减少重复
    - 简化条件逻辑和嵌套
    - 添加必要的类型标注
  '';

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
