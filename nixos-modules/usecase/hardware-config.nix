{ config, lib, pkgs, ... }:

{
  config = lib.mkMerge [
    # Intel 显卡配置
    (lib.mkIf (config.my.gpu == "intel") {
      hardware.opengl = {
        enable = true;
        extraPackages = with pkgs; [
          intel-media-driver
          intel-compute-runtime
        ];
      };
    })

    # NVIDIA 显卡配置
    (lib.mkIf (config.my.gpu == "nvidia") {
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        open = false;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };

      # 环境变量
      environment.sessionVariables = {
        LIBVA_DRIVER_NAME = "nvidia";
        GBM_BACKEND = "nvidia-drm";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      };
    })

    # AMD 显卡配置
    (lib.mkIf (config.my.gpu == "amd") {
      hardware.opengl = {
        enable = true;
        driSupport = true;
        extraPackages = with pkgs; [
          rocmPackages.clr.icd
          amdvlk
        ];
      };
    })

    # 双显卡混合配置
    (lib.mkIf (config.my.gpu == "hybrid") {
      hardware.nvidia.prime = {
        offload.enable = true;
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };

      # 环境变量
      environment.variables = {
        WLR_NO_HARDWARE_CURSORS = "1";
        NIXOS_OZONE_WL = "1";
      };
    })
  ];
}
