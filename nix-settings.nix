{ username, ... }:

{
  # Nix Configuration
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ]; # ✅ 启用flakes特性
    trusted-users = [ "root" username ];
    builders-use-substitutes = true; # ✅ 优先使用远程主机的构建，大幅缩短构建时间
    substituters = [
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://cache.nixos.org"
      "https://numtide.cachix.org"
      "https://devenv.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    ];

    # substituters = lib.mkForce ["https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store" "https://cache.nixos.org"]; # ✅ 使用清华镜像作为二进制缓存源
    # trusted-public-keys = ["cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="]; # ✅ 可信任的公钥，用于验证下载的包
  };

}
