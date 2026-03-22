#!/bin/bash
set -eo pipefail
disko_file_path="./config/disk-config.nix"

export NIX_CONFIG="experimental-features = nix-command flakes
substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store"

USING_SUBSTITUTERS="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://mirror.sjtu.edu.cn/nix-channels/store https://mirrors.cqupt.edu.cn/nix-channels/store https://cache.nixos.org"

BINARY_URL="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-25.11/nixexprs.tar.xz"

function init(){
    function prelude_func(){
        get_current_exe() {
            # Returns the executable used for system architecture detection
            # This is only run on Linux
            local _current_exe
            if test -L /proc/self/exe ; then
                _current_exe=/proc/self/exe
            else
                warn "Unable to find /proc/self/exe. System architecture detection might be inaccurate."
                if test -n "$SHELL" ; then
                    _current_exe=$SHELL
                else
                    need_cmd /bin/sh
                    _current_exe=/bin/sh
                fi
                warn "Falling back to $_current_exe."
            fi
            echo "$_current_exe"
        }
        __print() {
            if $_ansi_escapes_are_valid; then
                printf '\33[1m%s:\33[0m %s\n' "$1" "$2" >&2
            else
                printf '%s: %s\n' "$1" "$2" >&2
            fi
        }
        warn() {
            __print 'warn' "$1" >&2
        }
        say() {
            __print 'info' "$1" >&2
        }
        # NOTE: you are required to exit yourself
        # we don't do it here because of multiline errors
        err() {
            __print 'error' "$1" >&2
            exit 1
        }
        need_cmd() {
            if ! check_cmd "$1"; then
                err "need '$1' (command not found)"

            fi
        }
        check_cmd() {
            command -v "$1" > /dev/null 2>&1
        }
    }
    function get_architecture() {
        # local _ostype _cputype _arch
        _ostype="$(uname -s)"
        _cputype="$(uname -m)"
        if [ "$_ostype" = Linux ]; then
            if [ "$(uname -o)" = Android ]; then
                _ostype=Android
            elif [ -f /etc/os-release ]; then
                source /etc/os-release && [ "${ID:-}" = "nixos" ] && _ostype="NixOS"
            fi
        fi
        if [ "$_ostype" = Darwin ]; then
            # Darwin 系统下的 `uname -m` 命令可能因 Rosetta 兼容层的问题返回错误结果。
            # 理论上，如果能确保调用原生的 Shell 二进制文件和原生的 uname 二进制文件，
            # 可以获取真实的架构信息，但这一点很难保证。因此我们改用 `sysctl` 命令（该命令不会返回错误信息）
            # 来检测真实的 CPU 架构。
            if [ "$_cputype" = i386 ]; then
                # 处理运行在基于 x86_64 架构的 Mac 上的旧版 macOS（版本 <10.15）中的 i386 兼容模式。
                # 从 macOS 10.15 开始，苹果明确禁止所有 i386 架构的二进制文件运行。
                # 参考文档：<https://support.apple.com/en-us/HT208436>

                # 避免 `sysctl: unknown oid` 错误输出到标准错误流，同时避免非零退出码。
                if (sysctl hw.optional.x86_64 2> /dev/null || true) | grep -q ': 1'; then
                    _cputype=x86_64
                fi
            elif [ "$_cputype" = x86_64 ]; then
                # 处理运行在基于 arm64 架构的 Mac 上的新版 macOS（版本 >=11）中的 x86-64 兼容模式（也称为 Rosetta 2）。
                # Rosetta 2 仅为 x86-64 架构设计，无法运行 i386 架构的二进制文件。

                # 避免 `sysctl: unknown oid` 错误输出到标准错误流，同时避免非零退出码。
                if (sysctl hw.optional.arm64 2> /dev/null || true) | grep -q ': 1'; then
                    _cputype=arm64
                fi
            fi
        fi
        if [ "$_ostype" = SunOS ]; then
            # 不支持

            # 目前 Solaris 和 illumos 系统在执行 `uname -s` 时都会返回 "SunOS"，
            # 因此需要使用 `uname -o` 来区分二者。我们使用系统 uname 命令的完整路径，
            # 以避免用户的 PATH 环境变量中优先存在 coreutils 版本的 uname（该版本历史上曾在此处返回错误值）。
            if [ "$(/usr/bin/uname -o)" = illumos ]; then
                _ostype=illumos
            fi

            # illumos 系统支持多架构用户空间，`uname -m` 命令返回的是机器硬件名称；
            # 例如，在 32 位和 64 位 x86 系统上均返回 "i86pc"。
            # 此处检测运行中的内核所支持的原生（最宽）指令集：
            if [ "$_cputype" = i86pc ]; then
                _cputype="$(isainfo -n)"
            fi
        fi
        local _current_exe
        case "$_ostype" in
            Linux)
                _current_exe=$(get_current_exe)
                _ostype=linux
                ;;

            Darwin)
                _ostype=darwin
                ;;

            NixOS)
                _ostype=nixos
                ;;

            *)
                err "unrecognized OS type: $_ostype"

                ;;

        esac

        case "$_cputype" in
            aarch64 | arm64)
                _cputype=aarch64
                ;;

            x86_64 | x86-64 | x64 | amd64)
                _cputype=x86_64
                ;;

            *)
                err "unknown CPU type: $_cputype"
                ;;

        esac

        OS_TYPE="${_ostype}"
    }
    function live_cd_detect(){
        IS_LIVE_CD=$([ -f /proc/cmdline ] && grep -qE 'boot=live|live\.iso|nixos-live' /proc/cmdline 2>/dev/null && echo true || { mount | grep -qE ' / .*ro,' 2>/dev/null && [ -f /proc/mounts ] && grep -qE 'iso9660|squashfs' /proc/mounts 2>/dev/null && echo true || { [ -f /proc/mounts ] && grep -qE '/nix/store.*tmpfs|/nix/store.*overlay' /proc/mounts 2>/dev/null && echo true || echo false; }; })
        # IS_LIVE_CD=$([ $IS_LIVE_CD -eq 0 ] && echo true || echo false)
    }
    function executer_detect(){
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
        USER_HOME=$(eval echo ~"$USER_NAME")
    }
    # 让普通用户以sudo权限执行
    function use_sudo(){
        if [ "$IS_ROOT_USER" = false ] && [ "$IS_SUDO_USER" = false ]; then
            sudo -E "$@"  # 加引号，保留参数完整性, -E 保留环境变量
        else
            "$@"          # 加引号，保留参数完整性
        fi
    }
    function use_normal(){
        # 1. 先验证普通用户是否存在（安全校验）
        if ! id -u "$USER_NAME" >/dev/null 2>&1; then
            echo "错误：普通用户 $USER_NAME 不存在！" >&2
            return 1
        fi

        # 2. root/sudo用户切换到普通用户执行，否则直接执行
        if [ "$IS_ROOT_USER" = true ] || [ "$IS_SUDO_USER" = true ]; then
            # 使用 sudo -E 保留环境变量，同时设置 HOME
            # 注意：-E 需要 sudoers 配置，但通常对 root 有效
            # 使用 env 命令显式传递关键变量
            sudo -u "$USER_NAME" -E \
                HOME="$USER_HOME" \
                PATH="$PATH" \
                NIX_CONFIG="${NIX_CONFIG:-}" \
                "$@"
        else
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
    # 降级：root/sudo执行时以普通用户重新执行。 -E 保持环境变量不变
    function downgrade_privilege(){
        if [ "$EUID" -eq 0 ]; then
            exec sudo -u "$USER_NAME" -E HOME="$USER_HOME" bash "$0" "$@"
        fi
    }
    prelude_func
    executer_detect
    elevate_privilege
    # downgrade_privilege

    get_architecture
    say "Architecture: $_cputype"
    say "Operating System: $OS_TYPE"
    live_cd_detect
    say "Is Live CD: $IS_LIVE_CD"
    say "应用此配置的用户:$USER_NAME"
    say "IS_ROOT_USER:$IS_ROOT_USER"
    say "IS_SUDO_USER:$IS_SUDO_USER"
}
function nix_channel(){
    case "$OS_TYPE" in
        nixos)
            # say "正在添加 NixOS 仓库..."
            # if [ "$IS_ROOT_USER" = false ] && [ "$IS_SUDO_USER" = false ]; then
            #     sudo -E nix registry add nixpkgs $BINARY_URL
            #     nix registry add nixpkgs $BINARY_URL
            # else
            #     nix registry add nixpkgs $BINARY_URL
            # fi
            use_sudo nix registry add nixpkgs $BINARY_URL
            # nix registry add nixpkgs $BINARY_URL
            ;;
        linux)
            if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then # 多用户安装
                source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
                say "正在添加 Nix 仓库..."
                if [ "$IS_ROOT_USER" = true ] || [ "$IS_SUDO_USER" = true ]; then
                    nix registry add nixpkgs $BINARY_URL
                    su - "$USER_NAME" -c "USER=$USER_NAME HOME=$USER_HOME nix registry add nixpkgs $BINARY_URL"
                else
                    nix registry add nixpkgs $BINARY_URL
                fi
            elif [ -f $USER_HOME/.nix-profile/etc/profile.d/nix.sh ]; then # 单用户安装
                source $USER_HOME/.nix-profile/etc/profile.d/nix.sh
                say "正在添加 Nix 仓库..."
                nix registry add nixpkgs $BINARY_URL
            fi
            # if [ "$IS_MULTI_USER_INSTALLED" = true ]; then
            #     say "添加 NixOS 仓库..."
            #     use_sudo nix registry add nixpkgs $BINARY_URL
            # elif [ "$IS_SINGLE_USER_INSTALLED" = true ]; then
            #     say "添加 NixOS 仓库..."
            #     use_normal nix registry add nixpkgs $BINARY_URL
            # fi
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function partition_disk(){
    if [ "$OS_TYPE" = nixos ] && [ "$IS_LIVE_CD" = true ]; then
        say "当前是 NixOS Live CD"
        local mounts=$(grep -E '^/dev/(sd|nvme|vd|mmcblk|hd|xvd)' /proc/mounts | grep -v 'loop')
        if [ -n "$mounts" ]; then
            say "已挂载分区"
        else
            say "未挂载任何设备，正在分区..."
            if [ "$IS_ROOT_USER" = false ] && [ "$IS_SUDO_USER" = false ]; then
                sudo -E nix run nixpkgs#disko -- --mode disko $disko_file_path
            else
                nix run nixpkgs#disko -- --mode disko $disko_file_path
            fi
        fi
    fi
}
function pre_program_install(){
    case "$OS_TYPE" in
        nixos)
            if !(check_cmd git); then
                warn "git command not found"
                use_sudo nix --option extra-substituters "$USING_SUBSTITUTERS" profile add -f https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz git
            else
                say "git command found"
            fi
            if !(check_cmd lspci); then
                warn "lspci command not found"
                # if [ "$IS_ROOT_USER" = false ] && [ "$IS_SUDO_USER" = false ]; then
                #     sudo -E nix profile add nixpkgs#pciutils
                # else
                #     nix profile add nixpkgs#pciutils
                # fi
                use_sudo nix --option extra-substituters "$USING_SUBSTITUTERS" profile add -f https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz pciutils
            else
                say "lspci command found"
            fi
            ;;
        linux)
            # 1. 定义：命令名 → 包名（apt特殊包名用|分隔）
            local tools="curl:curl xz:xz|xz-utils git:git lspci:pciutils"
            local pkgs=() pm="" install_cmd=""

            # 2. 快速检查并收集缺失包
            for item in $tools; do
                cmd=${item%%:*} pkg=${item#*:}
                if ! check_cmd "$cmd"; then
                    pkgs+=(${pkg%|*})  # 取通用包名（|前的部分）
                fi
            done

            # 3. 无缺失直接返回
            [ ${#pkgs[@]} -eq 0 ] && { echo "所有工具均已安装"; return 0; }
            warn "需要安装: ${pkgs[*]}"

            # 4. 快速匹配包管理器（一行完成）
            check_cmd oma && pm="oma" && install_cmd="oma install -y"
            check_cmd apt && pm="apt" && install_cmd="apt install -y"
            check_cmd yum && pm="yum" && install_cmd="yum install -y"
            check_cmd dnf && pm="dnf" && install_cmd="dnf install -y"
            check_cmd apk && pm="apk" && install_cmd="apk install -y"
            check_cmd pacman && pm="pacman" && install_cmd="pacman -S --noconfirm"
            check_cmd zypper && pm="zypper" && install_cmd="zypper install -y"

            # 5. 处理apt特殊包名 + 执行安装
            [ "$pm" = "apt" ] && pkgs=(${pkgs[@]/xz/xz-utils})  # 替换xz为xz-utils
            [ "$pm" = "oma" ] && echo "安装慢可先执行: oma mirror"  # oma特殊提示
            if [ -n "$install_cmd" ]; then
                use_sudo $install_cmd ${pkgs[*]}
            else
                echo "无支持的包管理器，请手动安装: ${pkgs[*]}" && return 1
            fi
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function single_nix_install(){
    case "$OS_TYPE" in
        nixos)
            ;; # NixOS 不需要安装 Nix
        linux)
            bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add
            IS_SINGLE_USER_INSTALLED=true
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function multi_nix_install(){
    case "$OS_TYPE" in
        nixos)
            ;; # NixOS 不需要安装 Nix
        linux)
            NIX_INSTALLER_YES=1 bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add --daemon
            IS_MULTI_USER_INSTALLED=true
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function choose_install_nix_type(){
    case "$OS_TYPE" in
        nixos)
            ;; # NixOS 不需要安装 Nix
        linux)
            read -p "请选择安装类型：(1. 单用户安装 2. 多用户安装) " -r
            if [ "$REPLY" = "1" ]; then
                if [ "$IS_ROOT_USER" = true ] || [ "$IS_SUDO_USER" = true ]; then
                    warn "正在以普通用户重新执行脚本，单用户需要以普通用户执行"
                    downgrade_privilege
                fi
                single_nix_install
            elif [ "$REPLY" = "2" ]; then
                multi_nix_install
            else
                err "无效选择"
            fi
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function check_nix_install(){
    case "$OS_TYPE" in
        nixos)
            ;; # NixOS 不需要安装 Nix
        linux)
            IS_MULTI_USER_INSTALLED=false
            IS_SINGLE_USER_INSTALLED=false

            if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then # 多用户安装
                say "nix command found (多用户安装)"
                source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
                IS_MULTI_USER_INSTALLED=true
            elif [ -f $USER_HOME/.nix-profile/etc/profile.d/nix.sh ]; then # 单用户安装
                if [ "$IS_ROOT_USER" = true ] || [ "$IS_SUDO_USER" = true ]; then
                    warn "正在以普通用户重新执行脚本，单用户需要以普通用户执行"
                    downgrade_privilege
                fi
                say "nix command found (单用户安装)"
                source $USER_HOME/.nix-profile/etc/profile.d/nix.sh
                IS_SINGLE_USER_INSTALLED=true
            else
                warn "nix command not found"
                choose_install_nix_type
            fi

            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function nix_config(){
    case "$OS_TYPE" in
        nixos)
            ;;
        linux)
            function edit_nix_config(){
                if [ "$IS_MULTI_USER_INSTALLED" = true ]; then
                    local _nix_config_dir="/etc/nix"
                    echo "正在 $_nix_config_dir/nix.conf 创建nix配置..."
                    use_sudo mkdir -p $_nix_config_dir
                    use_sudo chmod 755 $_nix_config_dir  # 显式设置权限
                    use_sudo tee $_nix_config_dir/nix.conf << EOF
experimental-features = nix-command flakes # ✅ 启用flakes特性
trusted-users = root $USER_NAME # ✅ 多用户安装时，信任所有nix用户
substituters = $USING_SUBSTITUTERS # ✅ 使用清华和中科大镜像作为二进制缓存源
trusted-substituters = $USING_SUBSTITUTERS # ✅ 多用户安装时，信任所有二进制源
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= mirrors.tuna.tsinghua.edu.cn/nix-channels/store:rSzv032o86Rxxhl6/7aYRl0v56Kza+4+4G8q0aT+28A= mirrors.ustc.edu.cn/nix-channels/store:o9ien6A6Y75/32Jdl3lZF52E6hDUmD+86L948YH9QyU= # ✅ 可信任的公钥，用于验证下载的包
builders-use-substitutes = true # ✅ 优先使用远程主机的构建，大幅缩短构建时间
auto-optimise-store = true # ✅ 相同内容链接同一文件，减少重复存储
sandbox-fallback = false # ✅ 始终使用沙盒，失败不重复
EOF
                    # 清理 root 用户的配置（防止冲突）
                    if [ -f /root/.config/nix/nix.conf ]; then
                        warn "删除 root 用户配置文件 /root/.config/nix/nix.conf 以避免配置冲突"
                        use_sudo rm -rf /root/.config/nix/nix.conf
                    fi
                    # 清理普通用户的配置（防止冲突）
                    if [ -f $USER_HOME/.config/nix/nix.conf ]; then
                        warn "删除用户配置文件 $USER_HOME/.config/nix/nix.conf 以避免配置冲突"
                        use_sudo rm -rf $USER_HOME/.config/nix/nix.conf
                    fi

                elif [ "$IS_SINGLE_USER_INSTALLED" = true ]; then
                    local _nix_config_dir="$USER_HOME/.config/nix"
                    echo "正在 $_nix_config_dir/nix.conf 创建nix配置..."
                    use_normal mkdir -p $_nix_config_dir
                    use_normal chmod 755 $_nix_config_dir  # 显式设置权限
                    use_normal tee $_nix_config_dir/nix.conf << EOF
experimental-features = nix-command flakes # ✅ 启用flakes特性
substituters = $USING_SUBSTITUTERS # ✅ 使用清华和中科大镜像作为二进制缓存源
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= mirrors.tuna.tsinghua.edu.cn/nix-channels/store:rSzv032o86Rxxhl6/7aYRl0v56Kza+4+4G8q0aT+28A= mirrors.ustc.edu.cn/nix-channels/store:o9ien6A6Y75/32Jdl3lZF52E6hDUmD+86L948YH9QyU= # ✅ 可信任的公钥，用于验证下载的包
builders-use-substitutes = true # ✅ 优先使用远程主机的构建，大幅缩短构建时间
auto-optimise-store = true # ✅ 相同内容链接同一文件，减少重复存储
sandbox-fallback = false # ✅ 始终使用沙盒，失败不重复
EOF
                fi
            }
            function ensure_nixbld_group(){
                if [ "$IS_MULTI_USER_INSTALLED" = true ]; then
                    # 1. 给普通用户添加nixbld组（确保配置层面添加）
                    say "给普通用户添加nixbld组..."
                    use_sudo usermod -aG nixbld "$USER_NAME"

                    # 2. 验证：普通用户的组配置是否添加成功（/etc/group层面）
                    if ! id -nG "$USER_NAME" | grep -qw "nixbld"; then
                        echo "❌ 给 $USER_NAME 添加nixbld组失败，请手动检查！"
                        exit 1
                    fi

                    # 3. 验证：当前进程是否加载了nixbld组（缓存层面）
                    # 注意：这里查的是当前执行脚本的用户（比如root/sudo），如果是普通用户执行则查$USER
                    if ! id -nG "$USER_NAME" | grep -qw "nixbld" && [ "$GROUP_REFRESHED" -ne 1 ]; then
                        echo "🔄 nixbld组已添加，重启脚本使组生效..."
                        export GROUP_REFRESHED=1
                        exec "$SHELL" "$(realpath "$0")" "$@"  # 重启主脚本（必生效）
                    fi
                    echo "✅ nixbld组已生效，$USER_NAME 所在组：$(id -nG $USER_NAME)"
                fi
            }
            function daemon_reload(){
                if [ "$IS_MULTI_USER_INSTALLED" = true ]; then
                    say "重新加载 systemd 配置..."
                    sudo systemctl daemon-reload

                    say "重启 nix-daemon..."
                    # 修复：使用 restart 确保完全重启，而不是 stop + start
                    use_sudo systemctl restart nix-daemon.service

                    say "等待 nix-daemon 就绪..."
                    while ! use_sudo systemctl is-active --quiet nix-daemon.service; do sleep 1; done

                    # 修复：验证配置前先 source 环境变量
                    say "加载环境变量..."
                    if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
                        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
                    fi

                    say "验证配置..."
                    nix config show | grep -i "builders-use-substitutes = true"

                    say "验证配置..."
                    # 使用 nix config check 或直接测试命令
                    if ! nix store ping 2>/dev/null; then
                        warn "nix daemon 可能未正确响应"
                    fi
                    say "验证配置完成..."
                    # say "加载环境变量..."
                    # # source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true
                    # # source /etc/profile.d/nix.sh 2>/dev/null || true
                    # source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
                    # source /etc/profile.d/nix.sh
                fi
            }
            edit_nix_config
            ensure_nixbld_group
            # clear_cache # 在执行nix config show前清除缓存和配置
            fix_cache_permissions
            daemon_reload
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function choose_install_flake(){
    case "$OS_TYPE" in
        nixos)
            : # 无操作，NixOS默认应用flake配置
            ;;
        linux)
            read -p "应用flake配置？(Y/N，默认Y) " -r
            if [[ $REPLY =~ ^[Yy]$ ]] || [ -z $REPLY ]; then # (Y/N，默认Y)
                say "应用flake配置..."
            else
                say "不应用flake配置..."
                exit 0
            fi
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function cpu_detect(){
    case "$OS_TYPE" in
        nixos)
            ;;
        linux)
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function gpu_detect(){
    case "$OS_TYPE" in
        nixos)
            ;;
        linux)
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function virtualization_detect(){
    case "$OS_TYPE" in
        nixos)
            ;;
        linux)
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function hardware_config_generate(){
    case "$OS_TYPE" in
        nixos)
            ;;
        linux)
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function flake_load(){
    case "$OS_TYPE" in
        nixos)
            warn "已复制当前目录下的flake配置到/etc/nixos/"
            use_sudo cp -r ./* /etc/nixos/
            ;;
        linux)
            TARGET_DIR=$USER_HOME/.config/home-manager
            mkdir -p "$TARGET_DIR"
            warn "已复制当前目录下的flake配置到 $TARGET_DIR"
            cp -r ./* "$TARGET_DIR"
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function flake_apply(){
    case "$OS_TYPE" in
        nixos)
            if [ "$IS_LIVE_CD" = true ]; then
                warn "NixOS Live CD环境，正在使用flake配置安装系统"
                USER=$USER_NAME use_sudo nixos-install --option extra-substituters "$USING_SUBSTITUTERS" --flake /etc/nixos/ --impure
            else
                warn "NixOS环境，正在应用flake配置"
                USER=$USER_NAME use_sudo nixos-rebuild switch --option extra-substituters "$USING_SUBSTITUTERS" --flake /etc/nixos/ --impure
                # USER=$USER_NAME use_sudo nixos-rebuild switch --option extra-substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://cache.nixos.org" --flake /etc/nixos/ --impure
            fi
            ;;
        linux)
            if [ "$IS_MULTI_USER_INSTALLED" = true ]; then
                warn "多用户环境，正在应用flake配置"
                su - "$USER_NAME" -c "USER=$USER_NAME HOME=$USER_HOME nix run nixpkgs#home-manager -- switch --flake $USER_HOME/.config/home-manager --impure -b backup"
            else
                warn "单用户环境，正在应用flake配置"
                USER=$USER_NAME HOME=$USER_HOME nix run nixpkgs#home-manager -- switch --flake $USER_HOME/.config/home-manager --impure -b backup
            fi
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function congratulate(){
    echo "完成！"
    case "$OS_TYPE" in
        nixos)
            use_sudo nix --option extra-substituters "$USING_SUBSTITUTERS" run nixpkgs#hello
            ;;
        linux)
            if [ "$IS_ROOT_USER" = true ] || [ "$IS_SUDO_USER" = true ]; then
                su - "$USER_NAME" -c "USER=$USER_NAME HOME=$USER_HOME nix run nixpkgs#hello"
            else
                nix run nixpkgs#hello
            fi
            ;;
        darwin)
            ;;
        *)
            ;;
    esac
}
function clear_cache(){
    # 删除所有缓存和单用户配置，确保脚本执行后可用
    if [ "$IS_MULTI_USER_INSTALLED" = true ]; then
        if [ -d "/root/.cache/nix" ]; then
            use_sudo rm -rf /root/.cache/nix
        fi
        if [ -d "$USER_HOME/.cache/nix" ]; then
            use_sudo rm -rf "$USER_HOME/.cache/nix"
        fi
        if [ -d "$USER_HOME/.config/nix" ]; then
            # 会同时删除nix registry，所以不调用这个函数，改成调用fix_cache_permissions函数
            say "删除 $USER_HOME/.config/nix..."
            use_sudo rm -rf "$USER_HOME/.config/nix"
        fi
    fi
}
function fix_cache_permissions(){
    if [ "$IS_MULTI_USER_INSTALLED" = true ]; then
        # warn "多用户环境，正在修复缓存权限"
        local user_group="$(id -gn $USER_NAME 2>/dev/null || echo "$USER_NAME")"
        # 处理root目录（用use_sudo提权，直接写目录名，-Rf递归）
        [ -d "/root/.cache/nix" ] && use_sudo chown -Rf root:root /root/.cache/nix 2>/dev/null || true
        # 处理用户目录（拆分判断，避免一个目录不存在跳过全部，use_sudo提权）
        [ -d "$USER_HOME/.cache/nix" ] && use_sudo chown -Rf "$USER_NAME:$user_group" "$USER_HOME/.cache/nix" 2>/dev/null || true
        [ -d "$USER_HOME/.config/nix" ] && use_sudo chown -Rf "$USER_NAME:$user_group" "$USER_HOME/.config/nix" 2>/dev/null || true
        [ -d "$USER_HOME/.config/home-manager" ] && use_sudo chown -Rf "$USER_NAME:$user_group" "$USER_HOME/.config/home-manager" 2>/dev/null || true
    fi
}
main(){
    init
    nix_channel
    partition_disk
    pre_program_install
    check_nix_install
    nix_config
    nix_channel
    choose_install_flake
    cpu_detect
    gpu_detect
    virtualization_detect
    hardware_config_generate
    flake_load
    flake_apply
    congratulate
    # clear_cache
    fix_cache_permissions
}
main