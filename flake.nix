{
  description = "oh my nix configuration";
  inputs = {
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # ⚠️ 会从github下载
    # nixpkgs.url = "git+https://mirrors.tuna.tsinghua.edu.cn/git/nixpkgs.git?ref=nixos-unstable&shallow=1"; # ✅ shallow=1避免复制 .git
    nixpkgs.url = "git+https://mirrors.tuna.tsinghua.edu.cn/git/nixpkgs.git?ref=nixos-25.11&shallow=1"; # ✅ 国内源
    home-manager = {
      # 此flake来源
      # url = "github:nix-community/home-manager"; # ⚠️ 会从github下载
      # url = "git+https://gitcode.com/GitHub_Trending/ho/home-manager.git?ref=master"; # ✅ 快速高效的gitcode镜像
      url = "git+https://gitcode.com/GitHub_Trending/ho/home-manager.git?ref=release-25.11"; # ✅ 国内源
      # 此flake中的inputs.nixpkgs来源
      inputs.nixpkgs.follows = "nixpkgs"; # 依赖当前flake的输入
      # inputs.nixpkgs.url = "git+https://mirrors.tuna.tsinghua.edu.cn/git/nixpkgs.git?ref=nixos-unstable&shallow=1"; # ✅ 国内源
      # inputs.nixpkgs.url = "git+https://mirrors.tuna.tsinghua.edu.cn/git/nixpkgs.git?ref=nixos-25.11&shallow=1"; # ✅ 国内源
    };
    # nix-darwin = {
    #   # url = "github:nix-darwin/nix-darwin";
    #   url = "git+https://gitcode.com/gh_mirrors/ni/nix-darwin"; # ✅ 国内源
    #   # 此flake中的inputs.nixpkgs来源
    #   # inputs.nixpkgs.follows = "nixpkgs"; # ⚠️ 会从github下载
    #   # inputs.nixpkgs.url = "git+https://mirrors.tuna.tsinghua.edu.cn/git/nixpkgs.git?ref=nixos-unstable&shallow=1"; # ✅ 国内源
    #   inputs.nixpkgs.url = "git+https://mirrors.tuna.tsinghua.edu.cn/git/nixpkgs.git?ref=nixos-25.11&shallow=1"; # ✅ 国内源
    # };
    flake-parts = {
      # url = "github:hercules-ci/flake-parts"; # ⚠️ 会从github下载
      url = "git+https://gitcode.com/gh_mirrors/fl/flake-parts.git"; # ✅ 国内源
      inputs.nixpkgs-lib.follows = "nixpkgs"; # 依赖当前flake的输入
      # inputs.nixpkgs-lib.url = ""; # 还没找到镜像源
    };
    # flake-utils = {
    #   # url = "github:numtide/flake-utils"; # ⚠️ 会从github下载
    #   url = "git+https://gitcode.com/gh_mirrors/fl/flake-utils.git"; # ✅ 国内源
    # };
    # flake-utils-plus = {
    #   # url = "github:gytis-ivaskevicius/flake-utils-plus"; # ⚠️ 会从github下载
    #   url = "git+https://gitcode.com/gh_mirrors/fl/flake-utils-plus.git"; # ✅ 国内源
    # };
    # sops-nix = {
    #   url = "github:Mic92/sops-nix"; # 默认配置（但不直接使用）
    #   inputs.nixpkgs.follows = "nixpkgs"; # 强制使用nixpkgs里的包覆盖
    #   # url = "git+https://gitcode.com/gh_mirrors/so/sops-nix.git?ref=master&shallow=1"; # ✅ 国内源
    #   # url = "git+https://gitcode.com/gh_mirrors/so/sops-nix.git?ref=release-25.11&shallow=1" # ✅ 国内源
    #   # inputs.nixpkgs.url = "git+https://mirrors.tuna.tsinghua.edu.cn/git/nixpkgs.git?ref=nixos-unstable&shallow=1"; # ✅ 国内源
    #   # inputs.nixpkgs.url = "git+https://mirrors.tuna.tsinghua.edu.cn/git/nixpkgs.git?ref=nixos-25.11&shallow=1"; # ✅ 国内源
    # };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # 1. 显式定义支持的系统。flake-parts 会自动为这些系统生成对应的输出
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      # 2. 这里是 perSystem 部分，处理与具体架构相关的逻辑
      perSystem = { config, pkgs, system, ... }: {
        # 定义运行 `nix fmt .` 时使用的工具
        formatter = pkgs.nixpkgs-fmt;

        # 这里的 pkgs 已经根据上面的 systems 自动实例化好了
        # 如果你以后想定义自定义包，直接在这里写：
        # packages.default = pkgs.hello;
      };
      # 3. 这里是全局输出部分 (NixOS, Home Manager, 等)
      flake =
        let
          system = builtins.currentSystem;
          pkgs = nixpkgs.legacyPackages.${system};
          # 当前系统名称（优先使用 环境变量中的系统名；不支持时回退到 nixos）
          hostname =
            let
              host = builtins.getEnv "HOSTNAME";
            in
            if host != "" then host # 1. 优先使用 当前系统名称
            else "nixos";           # 2. 兜底使用 "nixos"
          # nixos版本配置
          myNixosVersion = "25.11";
          # 当前用户名（优先使用 环境变量中的用户名；不支持时回退到 default-user）
          # username =
          #   let
          #     sudoUser = builtins.getEnv "SUDO_USER";
          #     normalUser = builtins.getEnv "USER";
          #   in
          #   if sudoUser != "" then sudoUser          # 1. sudo执行时
          #   else if normalUser != "" then normalUser # 2. 普通执行时
          #   else "root";                             # 3. root执行时
          username = builtins.getEnv "USER";
        in
        {
          homeConfigurations."${username}" = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = { inherit inputs username myNixosVersion; };
            modules = [
              { nixpkgs.config.allowUnfree = true; } # TODO: 可以修改
              ./home.nix

            ];
          };
          # darwinConfigurations.${username} = nix-darwin.lib.darwinSystem {
          #   inherit pkgs;
          #   extraSpecialArgs = { inherit inputs username myNixosVersion; };
          #   modules = [
          #     { nixpkgs.config.allowUnfree = true; }
          #     ./home.nix
          #   ];
          # };
          nixosConfigurations."${hostname}" = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs username myNixosVersion; };
            modules = [
              # ./nixos.nix
              ./configuration.nix
              /etc/nixos/hardware-configuration.nix
              { nixpkgs.config.allowUnfree = true; } # TODO: 可以修改
              home-manager.nixosModules.home-manager
              {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  extraSpecialArgs = { inherit inputs username myNixosVersion; };
                  users.${username} = {
                    imports =
                      [
                        ./home.nix
                        ./nix-settings.nix
                      ];
                  };
                };
              }
            ];
          };
        };
    };
}
