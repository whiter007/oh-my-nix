#!/bin/bash
set -eo pipefail
# 初始化，脚本配置与环境信息获取
function init(){
    function script_setup(){
        function use_sudo(){
            if [[ ! $EUID -eq 0 ]]; then # 如果是普通用户执行脚本
                sudo "$@"
            else                         # 如果是sudo或者root用户执行脚本
                "$@"
            fi
        }
        # 提权，自动赋予此脚本执行权限
        function elevate_privilege(){
            if [[ ! -x "$0" ]]; then # 如果脚本没有执行权限
                echo "===== 正在赋予脚本执行权限 ====="
                use_sudo chmod +x "$0"
            fi
        }
        # 降级，以sudo执行时重新以普通用户执行
        function downgrade_privilege(){
            if [ -n "$SUDO_USER" ] && [ "$(id -u)" -eq 0 ]; then # 如果sudo环境变量存在，并且当前用户是root用户
                exec sudo -u "$SUDO_USER" \
                    HOME="$(eval echo ~"$SUDO_USER")" \
                    bash "$0" "$@"
            fi
        }
        elevate_privilege
        downgrade_privilege
    }
    function os_detect(){
        WHICH_DISTRO_ENV=""
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
        detect_which_distro_env
        echo "distro_env:$WHICH_DISTRO_ENV"
    }
    function live_cd_detect(){
        IS_LIVE_CD_ENV=false
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

        echo "live_cd_env:$IS_LIVE_CD_ENV"
    }
    function live_cd_install(){
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
        detect_live_cd_env
        if [ "$IS_LIVE_CD_ENV" = "true" ]; then
            echo "当前环境为Live CD"
        else
            echo "当前环境不是Live CD"
        fi
        detect_mounted_partition
        nixos_live_cd_install
    }

    # 执行者检查
    function user_detect(){
        function check_first_username(){
            if [[ "$IS_LIVE_CD_ENV" = "false" ]]; then
                local first_user=""
                while IFS=: read -r username _ uid _; do
                    if [[ "$uid" -ge 1000 ]] && [[ "$username" != "nobody" ]]; then
                        first_user="$username"
                        break
                    fi
                done < /etc/passwd
                echo "$first_user"
            fi
        }
        IS_ROOT_USER=false # root用户执行
        IS_SUDO_USER=false # sudo用户执行
        USER_NAME=$(whoami)          # 普通用户和root的执行者名字
        if [[ $EUID -eq 0 ]]; then       # 如果不是普通用户执行
            if [[ -n $SUDO_USER ]]; then # 如果是sudo用户执行
                IS_SUDO_USER=true
                USER_NAME=$SUDO_USER # sudo用户的执行者名字
            else                         # 如果是root用户执行
                IS_ROOT_USER=true
                USER_NAME=$(check_first_username)
            fi
        fi

        echo "应用此配置的用户:$USER_NAME"
        echo "IS_ROOT_USER:$IS_ROOT_USER"
        echo "IS_SUDO_USER:$IS_SUDO_USER"
    }
    # 脚本初始化
    script_setup

    echo "===== 系统环境检测 ====="
    # 操作系统环境检测
    os_detect

    echo "===== Live CD检测 ====="
    # Live CD环境检测
    live_cd_detect
    if [ "$IS_LIVE_CD_ENV" = "true" ]; then
        live_cd_install
    fi

    echo "===== 命令执行者检测 ====="
    # 用户检测
    user_detect
}
function nix_install(){
    if [ "$WHICH_DISTRO_ENV" == "nixos" ]; then    # NixOS环境
        echo "当前为NixOS，跳过安装nix"
        if command -v git >/dev/null 2>&1; then
            echo "git 已安装，跳过安装"
        else
            echo "正在安装 git"
            use_sudo nix --extra-experimental-features 'nix-command flakes' profile add -f https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz git --option substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store"
        fi

        if command -v lspci >/dev/null 2>&1; then
            echo "lspci 已安装，跳过安装"
        else
            echo "正在安装 lspci"
            use_sudo nix --extra-experimental-features 'nix-command flakes' profile add -f https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz pciutils --option substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store"
        fi
        echo 正在查看当前profile列表：
        nix --extra-experimental-features 'nix-command flakes' profile list
    elif [ "$WHICH_DISTRO_ENV" == "macos" ]; then  # macOS环境
        : # 无操作
    else                                           # linux环境
        # 检查 nix 是否已安装
        if command -v nix >/dev/null 2>&1; then
            echo "nix 已安装，跳过安装"
            NEED_TO_INSTALL_NIX=false
        fi
        # 检查并安装 curl、xz、git（网络请求和必要解压缩工具）。linux已稳定。TODO：增加darwin环境安装必要的工具的脚本
        function install_utils(){
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

            if ! command -v lspci >/dev/null 2>&1; then
                pkgs_to_install="$pkgs_to_install pciutils"
            fi

            # 如果所有工具都已安装，则跳过
            if [[ -z "$pkgs_to_install" ]]; then
                echo "curl、xz、git、pciutils 均已安装"
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
                use_sudo oma install -y $pkgs_to_install # ASOC系统
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
                use_sudo apt install -y $apt_pkgs # Debian/Ubuntu系列
            elif command -v yum >/dev/null 2>&1; then
                use_sudo yum install -y $pkgs_to_install # Redhat/CentOS系列
            elif command -v dnf >/dev/null 2>&1; then
                use_sudo dnf install -y $pkgs_to_install # Fedora系列
            elif command -v pacman >/dev/null 2>&1; then
                use_sudo pacman -S --noconfirm $pkgs_to_install # Arch Linux系列
            elif command -v zypper >/dev/null 2>&1; then
                use_sudo zypper install -y $pkgs_to_install # openSUSE系列
            else
                echo "未检测到支持的包管理器，请手动安装:$pkgs_to_install"
                return 1
            fi
        }
        # 检查nix是否已正确安装。TODO：增加darwin环境检查nix安装的脚本，并且解决在linux环境的检查问题
        function check_nix_install(){
            function uninstall_multi_user_nix(){
                use_sudo systemctl stop nix-daemon.service
                use_sudo systemctl disable nix-daemon.socket nix-daemon.service
                use_sudo systemctl daemon-reload
                use_sudo rm -rf /etc/nix /etc/bash.bashrc.backup-before-nix /etc/profile.d/nix.sh /etc/tmpfiles.d/nix-daemon.conf /nix ~root/.nix-channels ~root/.nix-defexpr ~root/.nix-profile ~root/.local/state/nix ~root/.cache/nix
                for i in $(seq 1 32); do
                    use_sudo userdel nixbld$i
                done
                use_sudo groupdel nixbld
            }
            NEED_TO_INSTALL_NIX=true
            if [[ $IS_ROOT_USER == true ]]; then # root用户执行
                if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
                    echo "nix已安装，检测到/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
                    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
                    NEED_TO_INSTALL_NIX=false
                else
                    if [ -f "/etc/bash.bashrc.backup-before-nix" ]; then
                        echo "检测nix卸载残留/etc/bash.bashrc.backup-before-nix，正在恢复配置"
                        # 将备份的原始配置恢复为当前配置
                        use_sudo mv /etc/bash.bashrc.backup-before-nix /etc/bash.bashrc
                    fi
                    NEED_TO_INSTALL_NIX=true
                fi
            else                                 # 普通用户和sudo用户执行
                if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
                    read -p "检测到nix已多用户安装，是否卸载？(Y/N，回车默认卸载): " -r
                    # 处理输入：空值（回车）或Y/y → 卸载；其他（N/n/其他）→ 保留
                    if [[ -z $REPLY || $REPLY =~ ^[Yy]$ ]]; then
                        echo "卸载nix多用户安装"
                        uninstall_multi_user_nix
                        NEED_TO_INSTALL_NIX=true
                    else
                        echo "保留nix多用户安装"
                    fi
                elif [ -f $(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh ]; then
                    echo "nix已安装，检测到$(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh"
                    source $(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh
                    NEED_TO_INSTALL_NIX=false
                fi
            fi

            if [[ $IS_SUDO_USER == true ]]; then
                NEED_TO_INSTALL_NIX=false
            fi
        }
        # linux环境安装nix已稳定。
        function install_nix(){
            # 如果是普通用户执行，执行单用户安装
            # 如果是root或者sudo用户执行，执行守护进程安装
            if [[ $IS_ROOT_USER == true ]]; then
                NIX_INSTALLER_YES=1 bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add --daemon
            else
                bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add
            fi
            # 尝试加载nix环境
            if [ -f $(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh ]; then
                source $(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh
            elif [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
                source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
            fi
        }
        install_utils
        check_nix_install
        if [[ $NEED_TO_INSTALL_NIX == true ]]; then
            install_nix
        fi
    fi
}
function hardware_detect(){
    # AI写的
    function os_in_container_detect(){
        IS_CONTAINER_ENV=false
        if [ -f /run/.containerenv ]; then
            echo "当前环境为容器"
            return 0
        fi
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
        echo "container_env:$IS_CONTAINER_ENV"
    }
    # 需要检测CPU厂商，因为不同厂商的CPU虚拟化支持不同
    function cpu_detect(){
        local cpu_model=$(lscpu | grep "Model name" | awk -F: '{print $2}' | xargs)
        echo "CPU型号: $cpu_model"
    }
    # AI写的
    function virtualization_support_detect() {
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
    # 这段是 https://gitlab.com/Zaney/zaneyos 中 install-zaneyos.sh 的132-198行直接扒下来的
    function gpu_detect(){
        echo "GPU Profile Detection"

        # Attempt automatic detection
        DETECTED_PROFILE=""

        has_nvidia=false
        has_intel=false
        has_amd=false
        has_vm=false

        if lspci | grep -qi 'vga\|3d\|display'; then
        while read -r line; do
            if echo "$line" | grep -qi 'nvidia'; then
            has_nvidia=true
            elif echo "$line" | grep -qi 'amd\|ati\|advanced micro devices'; then
            has_amd=true
            elif echo "$line" | grep -qi 'intel'; then
            has_intel=true
            elif echo "$line" | grep -qi 'virtio\|vmware'; then
            has_vm=true
            fi
        done < <(lspci | grep -i 'vga\|3d\|display')

        if $has_vm; then
            DETECTED_PROFILE="vm"
        elif $has_nvidia && $has_amd; then
            DETECTED_PROFILE="amd-nvidia-hybrid"
        elif $has_nvidia && $has_intel; then
            DETECTED_PROFILE="nvidia-laptop"
        elif $has_nvidia; then
            DETECTED_PROFILE="nvidia"
        elif $has_amd; then
            DETECTED_PROFILE="amd"
        elif $has_intel; then
            DETECTED_PROFILE="intel"
        fi
        fi

        # Handle detected profile or fall back to manual input
        if [ -n "$DETECTED_PROFILE" ]; then
        profile="$DETECTED_PROFILE"
        echo -e "${GREEN}Detected GPU profile: $profile${NC}"
        read -p "Correct? (Y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}GPU profile not confirmed. Falling back to manual selection.${NC}"
            profile="" # Clear profile to force manual input
        fi
        fi

        # If profile is still empty (either not detected or not confirmed), prompt manually
        if [ -z "$profile" ]; then
        echo -e "${RED}Automatic GPU detection failed or no specific profile found.${NC}"
        read -rp "Enter Your Hardware Profile (GPU)
        Options:
        [ amd ]
        amd-nvidia-hybrid
        intel
        nvidia
        nvidia-laptop
        vm
        Please type out your choice: " profile
        if [ -z "$profile" ]; then
            profile="amd"
        fi
        echo -e "${GREEN}Selected GPU profile: $profile${NC}"
        fi
    }
    echo "1. 容器检查"
    # 是否在容器中运行检查
    os_in_container_detect

    echo "2. CPU检测"
    # 检查CPU
    cpu_detect

    echo "3. 虚拟化支持检测"
    # 检测CPU虚拟化支持
    virtualization_support_detect

    echo "4. GPU检测"
    # 检查GPU
    gpu_detect

}
# 安装，根据环境类型执行不同的安装脚本
function install(){
    # 配置nix源。单用户或nix已稳定。TODO：待确认多用户安装和darwin环境。
    function nix_config(){
        # 配置系统nix源
        echo 正在配置flake的nixpkgs仓库...
        nix --extra-experimental-features 'nix-command flakes' registry add nixpkgs https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz
        echo 正在配置nix-系列命令的nixpkgs仓库...
        nix-channel --add https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz nixpkgs
        nix-channel --update

        # 脚本nix命令配置
        export NIX_CONFIG="experimental-features = nix-command flakes
substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store"
    }
    function nix_setting(){
        if [ "$WHICH_DISTRO_ENV" == "nixos" ]; then    # NixOS环境
            : # 无操作
        elif [ "$WHICH_DISTRO_ENV" == "macos" ]; then  # macOS环境
            : # 无操作
        else                                           # linux环境
            # 配置nix
            echo "正在创建nix配置..."
            if [ "$IS_ROOT_USER" == "true" ]; then
                : # 无操作
            else
                # 创建nix配置目录
                mkdir -p $(eval echo ~"$USER_NAME")/.config/nix
                tee $(eval echo ~"$USER_NAME")/.config/nix/nix.conf << EOF
experimental-features = nix-command flakes # ✅ 启用flakes特性
trusted-users = root $USER_NAME # ✅ 信任所有nix用户
substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://cache.nixos.org # ✅ 使用清华镜像作为二进制缓存源
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= # ✅ 可信任的公钥，用于验证下载的包
builders-use-substitutes = true # ✅ 优先使用远程主机的构建，大幅缩短构建时间
auto-optimise-store = true # ✅ 相同内容链接同一文件，减少重复存储
sandbox-fallback = false # ✅ 始终使用沙盒，失败不重复
EOF
            fi
        fi
    }
    function flake_load(){
        function check_flake(){
            if [ ! -f flake.nix ]; then
                echo "flake.nix 不存在，无法复制"
                return 1
            fi
        }
        if [ "$WHICH_DISTRO_ENV" == "nixos" ]; then    # NixOS环境
            if [[ $IS_LIVE_CD_ENV == true ]]; then
                check_flake
                echo "已复制/run/media/nixos/Ventoy/nix目录下的flake配置到/etc/nixos/"
                use_sudo cp -r ./* /etc/nixos/
            else
                check_flake
                echo "已复制当前目录下的flake配置到/etc/nixos/"
                use_sudo cp -r ./* /etc/nixos/
            fi
        elif [ "$WHICH_DISTRO_ENV" == "macos" ]; then  # macOS环境
            : # 无操作
        else                                           # linux环境
            if [ "$IS_ROOT_USER" == "true" ]; then
                check_flake
                echo "root用户执行，复制配置到普通用户 $USER_NAME 的目录"
                TARGET_DIR=$(eval echo ~"$USER_NAME")/.config/home-manager
                mkdir -p "$TARGET_DIR"
                echo "已复制当前目录下的flake配置到 $TARGET_DIR"
                cp -r ./* "$TARGET_DIR"
            else
                check_flake
                mkdir -p $(eval echo ~"$USER_NAME")/.config/home-manager/
                echo "已复制当前目录下的flake配置到 $(eval echo ~"$USER_NAME")/.config/home-manager/"
                cp -r ./* $(eval echo ~"$USER_NAME")/.config/home-manager/
            fi
        fi
    }
    function flake_apply(){
        if [ "$WHICH_DISTRO_ENV" == "nixos" ]; then    # NixOS环境
            if [ "$IS_LIVE_CD_ENV" == "true" ]; then
                echo "NixOS Live CD环境，正在应用flake配置"
                use_sudo nixos-rebuild switch --option substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store" --flake /etc/nixos/ --impure
            else
                echo "NixOS环境，正在应用flake配置"
                USER=$USER_NAME use_sudo nixos-rebuild switch --option substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store" --flake /etc/nixos/ --impure
            fi
        elif [ "$WHICH_DISTRO_ENV" == "macos" ]; then  # macOS环境
            : # 无操作
        else                                           # linux环境
            echo "非NixOS环境，正在应用home-manager配置"
            if [[ $IS_ROOT_USER == true ]]; then
                echo "root用户执行，切换到普通用户 $USER_NAME 应用配置"
                su - "$USER_NAME" -c "nix run nixpkgs#home-manager -- switch --flake ~/.config/home-manager/.#$USER_NAME --impure -b backup"
            else
                USER=$USER_NAME nix run nixpkgs#home-manager -- switch --flake $(eval echo ~"$USER_NAME")/.config/home-manager --impure -b backup
            fi
        fi
    }
    echo "1. 配置nix源"
    nix_config # 配置nix源和脚本变量
    nix_setting # 配置nix脚本安装后的nix
    echo "2. 复制flake配置"
    flake_load
    echo "3. 应用flake配置"
    flake_apply
}
function done(){
    echo "完成安装"
    if [[ $IS_ROOT_USER == true ]]; then
        su - "$USER_NAME" -c "nix run nixpkgs#fastfetch"
    else
        nix run nixpkgs#fastfetch
    fi
}

function main(){
    init
    echo ""
    echo "========= 安装nix及相关工具curl、xz、git、pciutils =========="
    nix_install
    # 让脚本生成配置适应当前硬件环境
    echo "===== 正在进行硬件环境检测 ====="
    hardware_detect
    echo "===== 正在应用配置 ====="
    install
}
main