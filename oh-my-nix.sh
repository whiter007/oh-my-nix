#!/bin/bash
# 初始化，脚本配置与环境信息获取
function init(){
    function setup(){
        # 执行者检查
        function check_executor(){
            echo "===== 检查命令执行者 ====="
            IS_ROOT_USER=false # root用户执行
            IS_SUDO_USER=false # sudo用户执行
            USERNAME=$(whoami)
            if [[ $EUID -eq 0 ]]; then
                if [[ -n $SUDO_USER ]]; then
                    IS_SUDO_USER=true
                    USERNAME=$SUDO_USER
                else
                    IS_ROOT_USER=true
                    # root直接执行时，查找系统上的第一个普通用户（UID >= 1000）
                    FIRST_NORMAL_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}')
                    if [[ -n "$FIRST_NORMAL_USER" ]]; then
                        USERNAME=$FIRST_NORMAL_USER
                        echo "检测到root执行，将使用系统普通用户: $USERNAME"
                    fi
                fi
            fi

            echo "EXECUTE_USER:$USERNAME"
            echo "IS_ROOT_USER:$IS_ROOT_USER"
            echo "IS_SUDO_USER:$IS_SUDO_USER"
        }
        # 提权，自动赋予此脚本执行权限
        function elevate_privilege(){
            if [[ ! -x "$0" ]]; then
                echo "===== 正在提权 ====="
                if [[ $IS_SUDO_USER == true ]]; then
                    chmod +x "$0"
                elif [[ $IS_ROOT_USER == true ]]; then
                    chmod +x "$0"
                else
                    sudo chmod +x "$0"
                fi
            fi
        }
        check_executor
        elevate_privilege
    }
    function detect_system_env(){
        echo "===== 正在检测系统环境 ====="
        IS_CONTAINER_ENV=false
        IS_LIVE_CD_ENV=false
        WHICH_DISTRO_ENV=""
        function detect_container_env(){
            if [[ -f /.dockerenv ]]; then
                IS_CONTAINER_ENV=true
                return
            fi
            if [[ -f /proc/1/cgroup ]] && grep -qE 'docker|containerd|kubepods|lxc' /proc/1/cgroup 2>/dev/null; then
                IS_CONTAINER_ENV=true
                return
            fi
            if [[ -n "${container:-}" ]]; then
                IS_CONTAINER_ENV=true
                return
            fi
            if grep -q 'container=' /proc/1/environ 2>/dev/null; then
                IS_CONTAINER_ENV=true
                return
            fi
        }
        function detect_live_cd_env(){
            if [[ -f /proc/mounts ]] && grep -qE 'overlay|aufs' /proc/mounts 2>/dev/null && grep -qE 'iso9660|squashfs' /proc/mounts 2>/dev/null; then
                IS_LIVE_CD_ENV=true
                return
            fi
            if [[ -d /lib/live ]]; then
                IS_LIVE_CD_ENV=true
                return
            fi
            if [[ -d /rofs ]]; then
                IS_LIVE_CD_ENV=true
                return
            fi
            if [[ -d /cdrom ]] && mountpoint -q /cdrom 2>/dev/null; then
                IS_LIVE_CD_ENV=true
                return
            fi
            if [[ -f /proc/cmdline ]] && grep -qE 'boot=live|liveimg|rd.live.image' /proc/cmdline 2>/dev/null; then
                IS_LIVE_CD_ENV=true
                return
            fi
        }
        function detect_which_distro_env(){
            if [[ "$(uname -s)" == "Darwin" ]]; then
                WHICH_DISTRO_ENV="macos"
                return
            fi
            if [[ -f /etc/os-release ]]; then
                local id=""
                source /etc/os-release
                if [[ -n "${ID:-}" ]]; then
                    WHICH_DISTRO_ENV="$ID"
                    return
                fi
            fi
            if [[ -f /etc/debian_version ]]; then
                WHICH_DISTRO_ENV="debian"
                return
            fi
            if [[ -f /etc/redhat-release ]]; then
                WHICH_DISTRO_ENV="rhel"
                return
            fi
            if [[ -f /etc/arch-release ]]; then
                WHICH_DISTRO_ENV="arch"
                return
            fi
            if [[ -f /etc/alpine-release ]]; then
                WHICH_DISTRO_ENV="alpine"
                return
            fi
            if [[ -f /etc/NIXOS ]]; then
                WHICH_DISTRO_ENV="nixos"
                return
            fi
        }
        detect_container_env
        detect_live_cd_env
        detect_which_distro_env
        echo "container_env:$IS_CONTAINER_ENV"
        echo "live_cd_env:$IS_LIVE_CD_ENV"
        echo "distro_env:$WHICH_DISTRO_ENV"
    }
    function detect_cpu_virtualization_support() {
        echo "===== 正在检测CPU虚拟化支持 ====="
        VIRTUALIZATION_SUPPORT=false
        NESTED_VIRT_ENABLED=false
        HYPERVISOR_TYPE="none"
        CPU_MODEL=""
        VIRT_TYPE=""

        # 获取CPU型号
        CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | xargs)

        # 检测虚拟化标志
        local virt_flags=$(grep -oE 'vmx|svm' /proc/cpuinfo 2>/dev/null)
        local virt_count=$(echo "$virt_flags" | grep -c .)

        # 确定虚拟化类型
        if echo "$virt_flags" | grep -q 'vmx'; then
            VIRT_TYPE="Intel VT-x"
        elif echo "$virt_flags" | grep -q 'svm'; then
            VIRT_TYPE="AMD-V"
        fi

        # 检测运行环境（虚拟机/物理机）
        local hypervisor=""

        # 方法1: systemd-detect-virt
        if command -v systemd-detect-virt &>/dev/null; then
            hypervisor=$(systemd-detect-virt 2>/dev/null)
            [ "$hypervisor" = "none" ] && hypervisor=""
        fi

        # 方法2: /sys/hypervisor/type (Xen)
        if [ -z "$hypervisor" ] && [ -f /sys/hypervisor/type ]; then
            hypervisor=$(cat /sys/hypervisor/type 2>/dev/null)
        fi

        # 方法3: CPU hypervisor标志
        if [ -z "$hypervisor" ] && grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
            hypervisor="unknown"
        fi

        # 方法4: DMI信息检测具体虚拟化平台
        if [ -f /sys/class/dmi/id/product_name ]; then
            local dmi_product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
            local dmi_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)

            case "$dmi_product$dmi_vendor" in
                *[Vv][Mm][Ww][Aa][Rr][Ee]*|*VMware*)
                    hypervisor="vmware"
                    ;;
                *[Vv][Ii][Rr][Tt][Uu][Aa][Ll][Bb][Oo][Xx]*|*VirtualBox*)
                    hypervisor="oracle"
                    ;;
                *[Mm][Ii][Cc][Rr][Oo][Ss][Oo][Ff][Tt]*[Cc][Oo][Rr][Pp]*|*Hyper-V*)
                    hypervisor="microsoft"
                    ;;
                *[Kk][Vv][Mm]*|*[Qq][Ee][Mm][Uu]*)
                    hypervisor="kvm"
                    ;;
                *[Xx][Ee][Nn]*)
                    hypervisor="xen"
                    ;;
                *[Pp][Aa][Rr][Aa][Ll][Ll][Ee][Ll][Ss]*)
                    hypervisor="parallels"
                    ;;
            esac
        fi

        # 方法5: 检查特定文件
        if [ -z "$hypervisor" ]; then
            if [ -d /proc/xen ]; then
                hypervisor="xen"
            elif [ -f /proc/vmware/version ]; then
                hypervisor="vmware"
            elif [ -f /proc/vz/veinfo ]; then
                hypervisor="openvz"
            fi
        fi

        # 标准化hypervisor名称
        case "$hypervisor" in
            vmware|VMware) HYPERVISOR_TYPE="VMware" ;;
            kvm|KVM) HYPERVISOR_TYPE="KVM/QEMU" ;;
            xen|Xen|xen-domU|xen-dom0) HYPERVISOR_TYPE="Xen" ;;
            oracle|virtualbox|VirtualBox) HYPERVISOR_TYPE="VirtualBox" ;;
            microsoft|hyperv|Hyper-V|hyper-v) HYPERVISOR_TYPE="Hyper-V" ;;
            parallels|Parallels) HYPERVISOR_TYPE="Parallels" ;;
            openvz|OpenVZ) HYPERVISOR_TYPE="OpenVZ" ;;
            docker|Docker) HYPERVISOR_TYPE="Docker" ;;
            wsl|WSL) HYPERVISOR_TYPE="WSL" ;;
            unknown) HYPERVISOR_TYPE="Unknown VM" ;;
            *) HYPERVISOR_TYPE="none" ;;
        esac

        # 判断逻辑
        if [ "$HYPERVISOR_TYPE" = "none" ]; then
            # 物理机环境
            if [ "$virt_count" -gt 0 ]; then
                VIRTUALIZATION_SUPPORT=true
                echo "当前环境为物理机，CPU支持硬件虚拟化 ($VIRT_TYPE)"
                echo "虚拟化核心数: $virt_count"
            else
                echo "当前环境为物理机，但CPU不支持硬件虚拟化或已在BIOS中禁用"
            fi
        else
            # 虚拟机环境
            if [ "$virt_count" -gt 0 ]; then
                NESTED_VIRT_ENABLED=true
                VIRTUALIZATION_SUPPORT=true
                echo "当前环境为$HYPERVISOR_TYPE虚拟机，且嵌套虚拟化已开启"
                echo "CPU型号: $CPU_MODEL"
                echo "虚拟化类型: $VIRT_TYPE"
            else
                echo "当前环境为$HYPERVISOR_TYPE虚拟机，且嵌套虚拟化未开启"
                echo "CPU型号: $CPU_MODEL"
                echo "提示: 请在虚拟机设置中启用'嵌套虚拟化'或'Expose hardware-assisted CPU virtualization to guest OS'"
            fi
        fi

        # 额外检查KVM可用性
        if [ "$VIRTUALIZATION_SUPPORT" = true ]; then
            if [ -e /dev/kvm ]; then
                if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
                    echo "KVM加速可用 (/dev/kvm)"
                else
                    echo "KVM设备存在但当前用户无权限，尝试: sudo chmod 666 /dev/kvm"
                fi
            else
                echo "KVM模块未加载，尝试: sudo modprobe kvm_intel 或 sudo modprobe kvm_amd"
            fi
        fi

        echo "VIRTUALIZATION_SUPPORT=$VIRTUALIZATION_SUPPORT"
    }
    function live_cd_install(){
        echo "===== 检查Live CD环境 ====="
        if [ "$IS_LIVE_CD_ENV" = "true" ]; then
            echo "当前环境为Live CD"
        else
            echo "当前环境不是Live CD"
        fi

        function detect_mounted_partition() {
            # 如果不是Live CD环境，直接返回
            if [ "$IS_LIVE_CD_ENV" != "true" ]; then
                echo "非Live CD环境，跳过挂载检测"
                HAS_MOUNTED_PARTITION=false
                return 1
            fi

            HAS_MOUNTED_PARTITION=false

            # 检测是否有物理磁盘分区被挂载（排除loop等虚拟设备）
            local mounts=$(grep -E '^/dev/(sd|nvme|vd|mmcblk|hd|xvd)' /proc/mounts | grep -v 'loop')

            if [ -n "$mounts" ]; then
                HAS_MOUNTED_PARTITION=true
                echo "Live CD环境：已检测到挂载的物理磁盘"
                echo "当前挂载情况："
                echo "$mounts" | awk '{print "  " $1 " -> " $2 " (" $3 ")"}'
                echo "即将开始安装系统"
                return 0
            else
                HAS_MOUNTED_PARTITION=false
                echo "Live CD环境：未检测到挂载的物理磁盘"
                echo "请先挂载目标磁盘到 /mnt"
                return 1
            fi
        }

        function nixos_live_cd_install(){
            if [ "$HAS_MOUNTED_PARTITION" = "true" ]; then
                echo "正在安装系统..."
            else
                echo "跳过系统安装（未检测到挂载的磁盘）"
            fi
        }
        detect_mounted_partition
        nixos_live_cd_install
    }
    setup
    detect_system_env
    detect_cpu_virtualization_support
    live_cd_install
}
# 安装，根据环境类型执行不同的安装脚本
function install(){
    function nix_install(){
        echo "1. 安装 nix"
        # 根据结果执行后续操作
        if [ "$WHICH_DISTRO_ENV" != "nixos" ]; then
            # 检查 nix 是否已安装
            if command -v nix >/dev/null 2>&1; then
                echo "nix 已安装，跳过安装"
                return 0
            fi

            function install_utils(){
                echo "正在检查并安装 curl、xz、git（网络请求和必要解压缩工具）"

                # 检查需要安装的包
                local pkgs_to_install=""

                if ! command -v curl >/dev/null 2>&1; then
                    pkgs_to_install="$pkgs_to_install curl"
                fi

                if ! command -v xz >/dev/null 2>&1; then
                    pkgs_to_install="$pkgs_to_install xz"
                fi

                if ! command -v git >/dev/null 2>&1; then
                    pkgs_to_install="$pkgs_to_install git"
                fi

                # 如果所有工具都已安装，则跳过
                if [[ -z "$pkgs_to_install" ]]; then
                    echo "curl、xz、git 均已安装，跳过安装"
                    return 0
                fi

                echo "需要安装的工具:$pkgs_to_install"

                # 根据系统选择包管理器
                if [ "$WHICH_DISTRO_ENV" == "macos" ]; then
                    if command -v brew >/dev/null 2>&1; then
                        echo "macOS环境，使用Homebrew安装"
                        brew install $pkgs_to_install
                    else
                        echo "未检测到Homebrew，请先安装Homebrew：/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                        exit 1
                    fi
                elif command -v oma >/dev/null 2>&1; then
                    echo "如果慢请先输入 oma mirror 命令以换源"
                    sudo oma install -y $pkgs_to_install # ASOC系统
                elif command -v apt >/dev/null 2>&1; then
                    # apt 包名特殊处理：xz 对应 xz-utils
                    local apt_pkgs=""
                    for pkg in $pkgs_to_install; do
                        if [[ "$pkg" == "xz" ]]; then
                            apt_pkgs="$apt_pkgs xz-utils"
                        else
                            apt_pkgs="$apt_pkgs $pkg"
                        fi
                    done
                    sudo apt install -y $apt_pkgs # Debian/Ubuntu系列
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y $pkgs_to_install # Redhat/CentOS系列
                elif command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y $pkgs_to_install # Fedora系列
                elif command -v pacman >/dev/null 2>&1; then
                    sudo pacman -S --noconfirm $pkgs_to_install # Arch Linux系列
                elif command -v zypper >/dev/null 2>&1; then
                    sudo zypper install -y $pkgs_to_install # openSUSE系列
                else
                    echo "未检测到支持的包管理器，请手动安装:$pkgs_to_install"
                    return 1
                fi
            }
            function install_nix(){
                if command -v nix >/dev/null 2>&1; then
                    echo "nix 已安装，跳过安装"
                    source ~/.nix-profile/etc/profile.d/nix.sh
                    return 0
                fi
                echo "正在安装 nix"
                # 清理之前安装留下的备份文件
                echo "清理之前安装留下的备份文件..."
                for backup_file in /etc/bash.bashrc.backup-before-nix /etc/zshrc.backup-before-nix /etc/profile.backup-before-nix; do
                    if [ -f "$backup_file" ]; then
                        echo "移除旧的备份文件: $backup_file"
                        rm -f "$backup_file"
                    fi
                done
                # 清理 /nix 目录（如果存在但 nix 命令不可用，说明是损坏的安装）
                if [ -d "/nix" ] && [ ! -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
                    echo "检测到损坏的 /nix 目录，正在清理..."
                    rm -rf /nix
                fi
                if [ "$IS_ROOT_USER" == "false" ] && [ "$IS_SUDO_USER" == "false" ]; then
                    bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add
                else
                    NIX_INSTALLER_YES=1 bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add --daemon
                fi
                source ~/.nix-profile/etc/profile.d/nix.sh
            }
            install_utils
            install_nix
        else
            echo "当前为NixOS，跳过安装nix"
            if command -v git >/dev/null 2>&1; then
                echo "git 已安装，跳过安装"
            else
                echo "正在安装 git"
                sudo nix --extra-experimental-features 'nix-command flakes' profile add -f https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz git --option substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store"
                echo 正在查看当前profile列表：
                nix --extra-experimental-features 'nix-command flakes' profile list
            fi
        fi
    }
    function nix_config(){
        echo "2. 配置nix源"
        if [ "$IS_ROOT_USER" == "true" ]; then
            echo "root用户执行，为普通用户 $USERNAME 配置nix源"
            su - "$USERNAME" -c "echo 正在配置flake的nixpkgs仓库...; nix --extra-experimental-features 'nix-command flakes' registry add nixpkgs https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz"
            su - "$USERNAME" -c "echo 正在配置nix-系列命令的nixpkgs仓库...; nix-channel --add https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz nixpkgs; nix-channel --update"
        else
            echo 正在配置flake的nixpkgs仓库...
            nix --extra-experimental-features 'nix-command flakes' registry add nixpkgs https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz
            echo 正在配置nix-系列命令的nixpkgs仓库...
            nix-channel --add https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz nixpkgs
            nix-channel --update
        fi
    }
    function flake_load(){
        echo "3. 复制flake配置"
        if [ "$WHICH_DISTRO_ENV" != "nixos" ]; then
            if [ "$IS_ROOT_USER" == "true" ]; then
                echo "root用户执行，复制配置到普通用户 $USERNAME 的目录"
                TARGET_DIR=$(eval echo ~"$USERNAME")/.config/home-manager
                mkdir -p "$TARGET_DIR"
                echo "已复制当前目录下的flake配置到 $TARGET_DIR"
                cp -r ./* "$TARGET_DIR"
            else
                mkdir -p ~/.config/home-manager/
                echo "已复制当前目录下的flake配置到 $(realpath ~/.config/home-manager)/"
                cp -r ./* ~/.config/home-manager/
            fi
        elif [[ $IS_LIVE_CD_ENV == true ]]; then
            echo "已复制/run/media/nixos/Ventoy/nix目录下的flake配置到/etc/nixos/"
            sudo cp -r /run/media/nixos/Ventoy/nix/* /etc/nixos/
        else
            echo "已复制当前目录下的flake配置到/etc/nixos/"
            sudo cp -r ./* /etc/nixos/
        fi
    }
    function flake_apply(){
        echo "4. 应用flake配置"
        if [ "$WHICH_DISTRO_ENV" == "macos" ]; then
            echo "macOS环境，正在应用home-manager配置（未实现）"
        elif [ "$WHICH_DISTRO_ENV" == "nixos" ] && [ "$IS_LIVE_CD_ENV" == "true" ]; then
            echo "NixOS Live CD环境，正在应用flake配置"
            sudo nixos-rebuild switch --option substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store" --flake /etc/nixos/ --impure
        elif [ "$WHICH_DISTRO_ENV" == "nixos" ]; then
            echo "NixOS环境，正在应用flake配置"
            sudo nixos-rebuild switch --option substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store" --flake /etc/nixos/ --impure
        else
            echo "非NixOS环境，正在应用home-manager配置"
            if [ "$IS_ROOT_USER" == "true" ]; then
                echo "root用户执行，切换到普通用户 $USERNAME 应用配置"
                su - "$USERNAME" -c "NIX_CONFIG=\"experimental-features = nix-command flakes\" nix --option substituters \"https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store\" run nixpkgs#home-manager -- switch --flake ~/.config/home-manager --impure -b backup"
            else
                NIX_CONFIG="experimental-features = nix-command flakes" nix --option substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store" run nixpkgs#home-manager -- switch --flake ~/.config/home-manager --impure -b backup
            fi
        fi
    }
    nix_install
    nix_config
    flake_load
    flake_apply
}
function done(){
    echo "完成安装"
    if [ "$IS_ROOT_USER" == "true" ]; then
        su - "$USERNAME" -c "nix --extra-experimental-features 'nix-command flakes' --option substituters \"https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store\" run nixpkgs#fastfetch"
    else
        nix --extra-experimental-features 'nix-command flakes' --option substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store" run nixpkgs#fastfetch
    fi
}

function main(){
    init
    install
}
main