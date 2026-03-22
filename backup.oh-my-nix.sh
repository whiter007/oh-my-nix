#!/bin/bash
set -eo pipefail
# 初始化，脚本配置与环境信息获取
function init(){
    function script_setup(){
        function use_sudo(){
            if [ ! $EUID -eq 0 ]; then # 如果是普通用户执行脚本
                sudo "$@"
            else                         # 如果是sudo或者root用户执行脚本
                "$@"
            fi
        }
        # 提权，自动赋予此脚本执行权限
        function elevate_privilege(){
            if [ ! -x "$0" ]; then # 如果脚本没有执行权限
                echo "===== 正在赋予脚本执行权限 ====="
                use_sudo chmod +x "$0"
            fi
        }
        # 降级，以sudo执行时重新以普通用户执行
        function downgrade_privilege(){
            if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
                exec sudo -u "$SUDO_USER" \
                    HOME="$(eval echo ~"$SUDO_USER")" \
                    bash "$0" "$@"
            fi
        }
        # 执行者检查
        function user_detect(){
            function check_first_username(){
                # 优先取sudo执行的原始用户 → 再取当前登录用户 → 最后取第一个普通用户（uid≥1000）
                echo "${SUDO_USER:-$(logname 2>/dev/null || awk -F: '$3>=1000 && $1!="nobody"{print $1;exit}' /etc/passwd)}"
            }
            IS_ROOT_USER=false # root用户执行
            IS_SUDO_USER=false # sudo用户执行
            USER_NAME=$(whoami)          # 普通用户和root的执行者名字
            if [ "$EUID" -eq 0 ]; then       # 如果不是普通用户执行
                if [ -n "$SUDO_USER" ]; then # 如果是sudo用户执行
                    IS_SUDO_USER=true
                    USER_NAME="$SUDO_USER"  # sudo用户的执行者名字
                else                         # 如果是root用户执行
                    IS_ROOT_USER=true
                    USER_NAME=$(check_first_username)
                fi
            fi

            echo "应用此配置的用户:$USER_NAME"
            echo "IS_ROOT_USER:$IS_ROOT_USER"
            echo "IS_SUDO_USER:$IS_SUDO_USER"
        }
        elevate_privilege
        downgrade_privilege
        echo "===== 命令执行者检测 ====="
        # 用户检测
        user_detect
    }
    function os_detect(){
        local _ostype _cputype _arch
        _ostype="$(uname -s)"
        _cputype="$(uname -m)"
        WHICH_DISTRO_ENV=""
        function detect_which_distro_env(){
            if [ "$(uname -s)" == "Darwin" ]; then
                WHICH_DISTRO_ENV="macos"
                return
            fi
            if [ -f /etc/os-release ]; then
                local id=""
                source /etc/os-release
                if [ -n "${ID:-}" ]; then
                    WHICH_DISTRO_ENV="$ID"
                    return
                fi
            fi
            if [ -f /etc/debian_version ]; then
                WHICH_DISTRO_ENV="debian"
                return
            fi
            if [ -f /etc/redhat-release ]; then
                WHICH_DISTRO_ENV="rhel"
                return
            fi
            if [ -f /etc/arch-release ]; then
                WHICH_DISTRO_ENV="arch"
                return
            fi
            if [ -f /etc/alpine-release ]; then
                WHICH_DISTRO_ENV="alpine"
                return
            fi
            if [ -f /etc/NIXOS ]; then
                WHICH_DISTRO_ENV="nixos"
                return
            fi
        }
        detect_which_distro_env
        echo "distro_env:$WHICH_DISTRO_ENV"
    }
    function live_cd_detect(){
        IS_LIVE_CD_ENV=false
        if [ -f /proc/mounts ] && grep -qE 'overlay|aufs' /proc/mounts 2>/dev/null && grep -qE 'iso9660|squashfs' /proc/mounts 2>/dev/null; then
            IS_LIVE_CD_ENV=true
            return
        fi
        if [ -d /lib/live ]; then
            IS_LIVE_CD_ENV=true
            return
        fi
        if [ -d /rofs ]; then
            IS_LIVE_CD_ENV=true
            return
        fi
        if [ -d /cdrom ] && mountpoint -q /cdrom 2>/dev/null; then
            IS_LIVE_CD_ENV=true
            return
        fi
        if [ -f /proc/cmdline ] && grep -qE 'boot=live|liveimg|rd.live.image' /proc/cmdline 2>/dev/null; then
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
        # 检查并安装 curl、xz、git、pciutils（网络请求和必要解压缩工具）。linux已稳定。TODO：增加darwin环境安装必要的工具的脚本
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
            if [ -z "$pkgs_to_install" ]; then
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
                    if [ "$pkg" == "xz" ]; then
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
        function uninstall_multi_user_nix(){
            read -p "检测到nix已多用户安装，是否卸载？(Y/N，默认N): " -r
            function backups_recover(){
                # 恢复系统级 zsh 配置
                if [ -f /etc/zshrc.backup-before-nix ]; then
                    use_sudo mv /etc/zshrc.backup-before-nix /etc/zshrc
                    # 仅当当前 shell 是 zsh 时才 source，避免 bash 执行 zsh 专属语法
                    if [ "$SHELL" = "/bin/zsh" ]; then
                        source /etc/zshrc
                    fi
                fi

                # 恢复系统级 bashrc 配置
                if [ -f /etc/bashrc.backup-before-nix ]; then
                    use_sudo mv /etc/bashrc.backup-before-nix /etc/bashrc
                    # 仅当当前 shell 是 bash 时才 source
                    if [ "$SHELL" = "/bin/bash" ]; then
                        source /etc/bashrc
                    fi
                fi

                # 恢复系统级 bash.bashrc 配置
                if [ -f /etc/bash.bashrc.backup-before-nix ]; then
                    use_sudo mv /etc/bash.bashrc.backup-before-nix /etc/bash.bashrc
                    # 仅当当前 shell 是 bash 时才 source
                    if [ "$SHELL" = "/bin/bash" ]; then
                        source /etc/bash.bashrc
                    fi
                fi
            }
            function daemon_stop_and_remove(){
                if [ "$WHICH_DISTRO_ENV" == "macos" ]; then
                    use_sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist
                    use_sudo rm /Library/LaunchDaemons/org.nixos.nix-daemon.plist
                    use_sudo launchctl unload /Library/LaunchDaemons/org.nixos.darwin-store.plist
                    use_sudo rm /Library/LaunchDaemons/org.nixos.darwin-store.plist
                else
                    use_sudo systemctl stop nix-daemon.service
                    use_sudo systemctl disable nix-daemon.socket nix-daemon.service
                    use_sudo rm -f /etc/systemd/system/nix-daemon.service
                    use_sudo rm -f /etc/systemd/system/nix-daemon.socket
                    use_sudo systemctl daemon-reload
                fi
            }
            function nixbld_group_and_users_remove(){
                if [ "$WHICH_DISTRO_ENV" == "macos" ]; then
                    use_sudo dscl . -delete /Groups/nixbld
                    for u in $(use_sudo dscl . -list /Users | grep _nixbld); do use_sudo dscl . -delete /Users/$u; done
                else
                    for i in $(seq 1 32); do
                        use_sudo userdel nixbld$i
                    done
                    use_sudo groupdel nixbld
                fi
            }
            function multi_nix_file_remove(){
                # 删除 Nix 主目录（核心存储）
                use_sudo rm -rf /nix
                # 删除 Nix 多用户安装的配置文件（可选，清理残留）
                use_sudo rm -rf ~root/.nix-profile
                use_sudo rm -rf ~root/.nix-channels
                use_sudo rm -rf ~root/.nix-defexpr
                use_sudo rm -rf /nix/var/nix/profiles/default/etc/nix
                use_sudo rm -rf /etc/nix
                # 删除 Nix 多用户安装的配置文件
                use_sudo rm -rf /etc/profile.d/nix.sh
                use_sudo rm -rf /etc/tmpfiles.d/nix-daemon.conf
                use_sudo rm -rf ~root/.local/state/nix
                use_sudo rm -rf ~root/.cache/nix
            }
            function macos_additional_remove(){
                :
            }
            # if [[ $REPLY =~ ^[Yy]$ ]] || [ -z $REPLY ]; then # (Y/N，默认Y)
            if [[ $REPLY =~ ^[Yy]$ ]]; then #(Y/N，默认N)
                echo "正在卸载nix多用户安装"
                backups_recover
                daemon_stop_and_remove
                nixbld_group_and_users_remove
                multi_nix_file_remove
                echo "按任意键继续..."
                read -r -n 1 -s  # -n 1 读取1个字符，-s 不回显输入
                NEED_TO_INSTALL_NIX=true
            else
                echo "保留nix多用户安装"
            fi
        }
        function uninstall_single_user_nix(){
            read -p "检测到nix已单用户安装，是否卸载？(Y/N，默认N): " -r
            # 恢复备份的shell配置文件
            function backups_recover(){
                # 定义用户主目录路径（避免重复拼接）
                local user_home=$(eval echo ~"$USER_NAME")

                # 恢复zsh配置
                if [ -f "${user_home}/.zshrc.backup" ]; then
                    use_sudo mv "${user_home}/.zshrc.backup" "${user_home}/.zshrc"
                    # 仅当当前shell是zsh时才source，避免bash执行zsh语法
                    if [ "$SHELL" = "/bin/zsh" ]; then
                        source "${user_home}/.zshrc"
                    fi
                fi

                # 恢复bashrc（修复：source对应的bashrc）
                if [ -f "${user_home}/.bashrc.backup" ]; then
                    use_sudo mv "${user_home}/.bashrc.backup" "${user_home}/.bashrc"
                    # 仅当当前shell是bash时才source
                    if [ "$SHELL" = "/bin/bash" ]; then
                        source "${user_home}/.bashrc"
                    fi
                fi

                # 恢复bash.bashrc（修复：source对应的bash.bashrc）
                if [ -f "${user_home}/.bash.bashrc.backup" ]; then
                    use_sudo mv "${user_home}/.bash.bashrc.backup" "${user_home}/.bash.bashrc"
                    # 仅当当前shell是bash时才source
                    if [ "$SHELL" = "/bin/bash" ]; then
                        source "${user_home}/.bash.bashrc"
                    fi
                fi
            }
            function single_nix_file_remove(){
                # 删除 Nix 主目录（核心存储）
                use_sudo rm -rf /nix
                # 删除用户级 Nix 配置（可选，清理残留）
                rm -rf $(eval echo ~"$USER_NAME")/.nix-profile
                rm -rf $(eval echo ~"$USER_NAME")/.nix-defexpr
                rm -rf $(eval echo ~"$USER_NAME")/.nix-channels
                rm -rf $(eval echo ~"$USER_NAME")/.config/nix
            }
            # if [[ $REPLY =~ ^[Yy]$ ]] || [ -z $REPLY ]; then # (Y/N，默认Y)
            if [[ $REPLY =~ ^[Yy]$ ]]; then #(Y/N，默认N)
                backups_recover
                single_nix_file_remove
                echo "按任意键继续..."
                read -r -n 1 -s  # -n 1 读取1个字符，-s 不回显输入
                NEED_TO_INSTALL_NIX=true
            else
                echo "保留nix单用户安装"
            fi
        }
        function check_conflict_nix(){
            local _is_multi_user_installed=false
            local _is_single_user_installed=false
            NEED_TO_INSTALL_NIX=false

            if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then # 多用户安装
                source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
                _is_multi_user_installed=true
            elif [ -f $(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh ]; then # 单用户安装
                source $(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh
                _is_single_user_installed=true
            fi

            if [ "$IS_ROOT_USER" == "false" ] && [ "$IS_SUDO_USER" == "false" ]; then # 普通用户执行脚本
                if [ "$_is_multi_user_installed" == "true" ]; then
                    echo "nix已多用户安装，检测到/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
                    uninstall_multi_user_nix
                elif [ "$_is_single_user_installed" == "true" ]; then
                    echo "nix已单用户安装，检测到$(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh"
                else
                    echo "nix未安装"
                    NEED_TO_INSTALL_NIX=true
                fi
            else                                                                      # root或者sudo用户执行脚本
                if [ "$_is_single_user_installed" == "true" ]; then
                    echo "nix已单用户安装，检测到$(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh"
                    uninstall_single_user_nix
                elif [ "$_is_multi_user_installed" == "true" ]; then
                    echo "nix已多用户安装，检测到/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
                else
                    echo "nix未安装"
                    NEED_TO_INSTALL_NIX=true
                fi
            fi
        }
        # linux环境安装nix已稳定。
        function install_nix(){
            # 如果是普通用户执行，执行单用户安装
            # 如果是root或者sudo用户执行，执行守护进程安装
            if [ "$IS_ROOT_USER" == "false" ] && [ "$IS_SUDO_USER" == "false" ]; then
                bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add
            else
                rm -rf /etc/zshrc.backup-before-nix # 删除备份文件,避免安装失败
                rm -rf /etc/bashrc.backup-before-nix # 删除备份文件,避免安装失败
                rm -rf /etc/bash.bashrc.backup-before-nix # 删除备份文件,避免安装失败
                NIX_INSTALLER_YES=1 bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add --daemon
            fi
            # 尝试加载nix环境
            if [ -f $(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh ]; then
                source $(eval echo ~"$USER_NAME")/.nix-profile/etc/profile.d/nix.sh
            elif [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
                source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
            fi
        }
        install_utils
        check_conflict_nix
        if [ "$NEED_TO_INSTALL_NIX" == "true" ]; then
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
        if [ -f /.dockerenv ]; then
            IS_CONTAINER_ENV=true
            return
        fi
        if [ -f /proc/1/cgroup ] && grep -qE 'docker|containerd|kubepods|lxc' /proc/1/cgroup 2>/dev/null; then
            IS_CONTAINER_ENV=true
            return
        fi
        if [ -n "${container:-}" ]; then
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
            if [[ $REPLY =~ ^[Yy]$ ]]; then #(Y/N，默认N)
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
        if [ "$IS_ROOT_USER" == "true" ]; then
            echo "root用户执行，切换到普通用户 $USER_NAME 执行"
            su - "$USER_NAME" -c "
            echo 正在配置flake的nixpkgs仓库...
            nix --extra-experimental-features 'nix-command flakes' registry add nixpkgs https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz
            echo 正在配置nix-系列命令的nixpkgs仓库...
            nix-channel --add https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz nixpkgs
            nix-channel --update
            "
        else
            echo 正在配置flake的nixpkgs仓库...
            nix --extra-experimental-features 'nix-command flakes' registry add nixpkgs https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz
            echo 正在配置nix-系列命令的nixpkgs仓库...
            nix-channel --add https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz nixpkgs
            nix-channel --update
        fi

        # 脚本nix命令配置
        export NIX_CONFIG="experimental-features = nix-command flakes
substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store"
    }
    function nix_setting(){
        function restart_nix_daemon(){
            echo "正在停止nix-daemon服务..."
            systemctl stop nix-daemon.socket nix-daemon.service && sleep 2

            # 2. 等待配置生效（最多等5秒，验证trusted-users是否包含目标用户）
            # for i in {1..5}; do
            #     if nix config show trusted-users | grep -q "$USER_NAME"; then
            #     break  # 配置生效，退出循环
            #     fi
            #     sleep 1
            # done
            # 2. 刷新用户组（无需重新登录）
            echo "正在刷新用户组..."
            usermod -aG nixbld "$USER_NAME"  # 确保用户在nixbld组
            # 3. 启动服务（不重启socket，避免冲突）
            echo "正在启动nix-daemon服务..."
            systemctl start nix-daemon.service
            # 4. 刷新权限（不重启脚本，仅刷新组）
            echo "正在刷新权限..."
            newgrp nixbld << EOF >/dev/null 2>&1
exit
EOF
        }
        if [ "$WHICH_DISTRO_ENV" == "nixos" ]; then    # NixOS环境
            : # 无操作
        elif [ "$WHICH_DISTRO_ENV" == "macos" ]; then  # macOS环境
            : # 无操作
        else                                           # linux环境
            # 配置nix
            NIX_CONFIG_DIR="/etc/nix"
            echo "正在 $NIX_CONFIG_DIR 创建nix配置..."
            if [ "$IS_ROOT_USER" == "true" ]; then
                # 创建nix配置目录
                mkdir -p $NIX_CONFIG_DIR
                tee $NIX_CONFIG_DIR/nix.conf << EOF
experimental-features = nix-command flakes # ✅ 启用flakes特性
trusted-users = root $USER_NAME # ✅ 信任所有nix用户
substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://cache.nixos.org # ✅ 使用清华镜像作为二进制缓存源
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= # ✅ 可信任的公钥，用于验证下载的包
builders-use-substitutes = true # ✅ 优先使用远程主机的构建，大幅缩短构建时间
auto-optimise-store = true # ✅ 相同内容链接同一文件，减少重复存储
sandbox-fallback = false # ✅ 始终使用沙盒，失败不重复
EOF
                restart_nix_daemon
            fi
            # 创建用户nix配置目录
            mkdir -p $(eval echo ~"$USER_NAME")/.config/nix
            tee $(eval echo ~"$USER_NAME")/.config/nix/nix.conf << EOF
experimental-features = nix-command flakes # ✅ 启用flakes特性
substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://cache.nixos.org # ✅ 使用清华镜像作为二进制缓存源
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= # ✅ 可信任的公钥，用于验证下载的包
builders-use-substitutes = true # ✅ 优先使用远程主机的构建，大幅缩短构建时间
auto-optimise-store = true # ✅ 相同内容链接同一文件，减少重复存储
sandbox-fallback = false # ✅ 始终使用沙盒，失败不重复
EOF
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
            if [ "$IS_LIVE_CD_ENV" == "true" ]; then
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
            check_flake
            TARGET_DIR=$(eval echo ~"$USER_NAME")/.config/home-manager
            mkdir -p "$TARGET_DIR"
            echo "已复制当前目录下的flake配置到 $TARGET_DIR"
            cp -r ./* "$TARGET_DIR"
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
            if [ "$IS_ROOT_USER" == "true" ]; then
                echo "root用户执行，切换到普通用户 $USER_NAME 应用配置"
                # su - "$USER_NAME" -c "
                sudo -i -u "$USER_NAME" bash -c "
                    export HOME=/home/$USER_NAME;
                    nix run nixpkgs#home-manager -- switch --flake $(eval echo ~"$USER_NAME")/.config/home-manager --impure -b backup
                "
                # su - "$USER_NAME" -c "nix run nixpkgs#home-manager -- switch --flake ~/.config/home-manager/.#$USER_NAME --impure -b backup"
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
    if [ "$IS_ROOT_USER" == "true" ]; then
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