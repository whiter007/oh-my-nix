{  # 使用 disko 进行分区配置
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # 根据需要修改设备路径，例如 /dev/sda, /dev/nvme0n1, /dev/vda 等
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            # EFI 系统分区
            ESP = {
              type = "EF00";  # EFI 系统分区类型
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat"; # fat32
                mountpoint = "/boot";
                mountOptions = [
                  "defaults"
                  "umask=0077"  # 安全挂载选项
                ];
              };
            };

            # 根分区，使用剩余所有空间
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4"; # ext4
                mountpoint = "/";
                mountOptions = [
                  "defaults"
                  "noatime"     # 提升 SSD 性能
                  "nodiratime"
                ];
              };
            };
          };
        };
      };
    };
  };
}
