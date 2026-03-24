{ config, pkgs, lib, inputs, myUsername, ... }:

{
    # 定义你的用户账户. 别忘了使用 'passwd' 设置密码
    users.users."${myUsername}" = {
        isNormalUser = true;
        home = "/home/${myUsername}";
        description = "${myUsername}";
        extraGroups = [ "networkmanager" "wheel" ];
        initialPassword = "root";  # 临时密码，首次登录后会要求更改
        packages = with pkgs; [
        # thunderbird
        ];
    };
}