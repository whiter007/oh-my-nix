{ config, lib, pkgs, ... }:

let
  cudaEnv = pkgs.buildEnv {
    name = "cuda-env";
    paths = [
      pkgs.cudaPackages.cudatoolkit.lib # ← 只拿 lib 输出
      pkgs.cudaPackages.cudnn.lib # ← 只拿 lib 输出
    ];
    ignoreCollisions = true;
  };
in
{
  home.packages = [
    cudaEnv
    pkgs.nvidia-container-toolkit
    # 再把二进制也带上，否则 nvcc 会消失
    pkgs.cudaPackages.cudatoolkit
  ];

  home.sessionVariables = {
    CUDA_HOME = "${pkgs.cudaPackages.cudatoolkit}"; # 把头文件目录指回完整包
    LD_LIBRARY_PATH = "${cudaEnv}/lib";
    # LD_LIBRARY_PATH = "${cudaEnv}/lib:$LD_LIBRARY_PATH";
    # PATH = lib.mkForce "${cudaEnv}/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH";
  };
}
#   # 添加NVIDIA相关的shell别名
#   programs.bash.shellAliases = lib.mkIf config.programs.bash.enable {
#     nvidia-smi = "nvidia-smi";
#     nvtop = "nvtop";
#   };

#   programs.zsh.shellAliases = lib.mkIf config.programs.zsh.enable {
#     nvidia-smi = "nvidia-smi";
#     nvtop = "nvtop";
#   };
# }
