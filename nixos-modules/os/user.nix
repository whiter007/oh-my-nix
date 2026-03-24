{ config, pkgs, lib, inputs, userName, ... }:

{
    # 定义你的用户账户. 别忘了使用 'passwd' 设置密码
    users.users."${userName}" = {
        isNormalUser = true;
        home = "/home/${userName}";
        description = "${userName}";
        extraGroups = [ "networkmanager" "wheel" ];
        packages = with pkgs; [
        # thunderbird
        ];
    };
}