{ config, lib, pkgs, ... }:

{
  # 安装 ROCm 相关包
  home.packages = with pkgs; [
    rocmPackages.llvm.llvm
    rocmPackages.hipcc
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
  ];

  # 设置ROCm相关环境变量
  home.sessionVariables = {
    ROCM_PATH = "${pkgs.rocmPackages.clr}";
    HIP_PATH = "${pkgs.rocmPackages.hipcc}";
    LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.hipcc}/lib:$LD_LIBRARY_PATH";
  };

  # 添加ROCm相关的shell别名
  programs.bash.shellAliases = lib.mkIf config.programs.bash.enable {
    rocm-smi = "rocm-smi";
    rocminfo = "rocminfo";
  };

  programs.zsh.shellAliases = lib.mkIf config.programs.zsh.enable {
    rocm-smi = "rocm-smi";
    rocminfo = "rocminfo";
  };
}
