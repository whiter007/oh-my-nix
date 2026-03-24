{ config, pkgs, lib, myUsername, myNixosVersion, ... }:

let
  modulesPath = ../home-modules;
in
{
  imports =
    [
      # home-manager相关配置
      (modulesPath + /infrastructure/user.nix) # home-manager 核心配置
      # 软件包管理
      (modulesPath + /infrastructure/git.nix) # 基础
      (modulesPath + /infrastructure/ssh.nix) # 基础
      (modulesPath + /infrastructure/shells.nix) # 终端配置
      (modulesPath + /infrastructure/starship.nix) # 终端美化和加速
      # (modulesPath + /infrastructure/direnv.nix) # 终端自动化工具
      # (modulesPath + /infrastructure/devenv.nix) # 终端自动化工具
      # (modulesPath + /infrastructure/nvidia-toolkit.nix) # NVIDIA GPU支持
      # (modulesPath + /infrastructure/rocm.nix) # AMD GPU支持 635.0 MiB
      # (modulesPath + /development/build-dep/c.nix) # C语言编译器
      # (modulesPath + /development/build-dep/python.nix)
      # (modulesPath + /development/editer/neovim.nix) # 终端编辑器 444.5 MiB
      # (modulesPath + /development/editer/lazy-neovim.nix) # 终端编辑器
      # (modulesPath + /development/ai/gemini-cli.nix) # 终端AI助手 287.6 MiB
      # (modulesPath + /development/ai/claude-code.nix) # 终端AI助手 709.7 MiB
      # (modulesPath + /development/ai/qwen-code.nix) # 终端AI助手 180.9 MiB
      # (modulesPath + /development/ai/aider.nix) # 终端AI助手 1.8 GiB 使用openrouter
      # (modulesPath + /development/ai/opencode.nix) # 终端AI助手 135.9 MiB
      # (modulesPath + /development/ai/ollama.nix) # 本地AI服务 53.7 MiB
    ];
}
