{ config, pkgs, lib, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "whiter007"; # ⚠️ 修改为你的名字
        email = "whiter007@qq.com"; # ⚠️ 修改为你的邮箱
      };
    };
    ignores = [
      "secrets.env"
      ".env"
      ".DS_Store"
      "*.swp"
      "*.swo"
      "node_modules/"
      "dist/"
      "result/"
    ];
  };
}
