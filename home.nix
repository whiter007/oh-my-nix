{ config, pkgs, lib, username, myNixosVersion, ... }:

let
  modulesPath = ./hm-modules;
in
{
  imports =
    [
      # home-manager相关配置
      (modulesPath + /user.nix) # home-manager 核心配置
      # 软件包管理
      (modulesPath + /git.nix) # 基础
      (modulesPath + /ssh.nix) # 基础
      (modulesPath + /shell/shells.nix) # 终端配置
      (modulesPath + /shell/starship.nix) # 终端美化和加速
      # (modulesPath + /shell/direnv.nix) # 终端自动化工具
      # (modulesPath + /shell/devenv.nix) # 终端自动化工具
      # (modulesPath + /build-dep/c.nix) # C语言编译器
      # (modulesPath + /build-dep/python.nix)
      # (modulesPath + /editer/neovim.nix) # 终端编辑器 444.5 MiB
      # (modulesPath + /editer/lazy-neovim.nix) # 终端编辑器
      # (modulesPath + /ai/gemini-cli.nix) # 终端AI助手 287.6 MiB
      # (modulesPath + /ai/claude-code.nix) # 终端AI助手 709.7 MiB
      # (modulesPath + /ai/qwen-code.nix) # 终端AI助手 180.9 MiB
      # (modulesPath + /ai/aider.nix) # 终端AI助手 1.8 GiB 使用openrouter
      # (modulesPath + /ai/opencode.nix) # 终端AI助手 135.9 MiB
      # (modulesPath + /ai/ollama.nix) # 本地AI服务 53.7 MiB
      # (modulesPath + /nvidia-toolkit.nix) # NVIDIA GPU支持
      # (modulesPath + /rocm.nix) # AMD GPU支持 635.0 MiB
    ];
}
