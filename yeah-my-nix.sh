#!/bin/bash
set -eo pipefail

USING_SUBSTITUTERS="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://mirror.sjtu.edu.cn/nix-channels/store https://mirrors.cqupt.edu.cn/nix-channels/store https://cache.nixos.org"
readonly BINARY_URL="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz"
readonly DISKO_FILE_PATH="${PWD}/config/disko-config.nix" # 绝对路径

export NIX_CONFIG="experimental-features = nix-command flakes
substituters = $USING_SUBSTITUTERS"
# export NIX_CONFIG="experimental-features = nix-command flakes
# substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz"

FLAKE_CONF_CONTENT=$(cat << EOF
experimental-features = nix-command flakes
trusted-users = root $USER_NAME  # 若需要替换变量，去掉EOF的单引号
substituters = $USING_SUBSTITUTERS
trusted-substituters = $USING_SUBSTITUTERS
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= mirrors.tuna.tsinghua.edu.cn/nix-channels/store:rSzv032o86Rxxhl6/7aYRl0v56Kza+4+4G8q0aT+28A=
builders-use-substitutes = true
auto-optimise-store = true
sandbox-fallback = false
EOF
)

NIX_CONF_CONTENT=$(cat << EOF
experimental-features = nix-command flakes # ✅ 启用flakes特性
trusted-users = root $USER_NAME # ✅ 多用户安装时，信任所有nix用户
substituters = $USING_SUBSTITUTERS # ✅ 使用清华和中科大镜像作为二进制缓存源
trusted-substituters = $USING_SUBSTITUTERS # ✅ 多用户安装时，信任所有二进制源
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= mirrors.tuna.tsinghua.edu.cn/nix-channels/store:rSzv032o86Rxxhl6/7aYRl0v56Kza+4+4G8q0aT+28A= mirrors.ustc.edu.cn/nix-channels/store:o9ien6A6Y75/32Jdl3lZF52E6hDUmD+86L948YH9QyU= # ✅ 可信任的公钥，用于验证下载的包
builders-use-substitutes = true # ✅ 优先使用远程主机的构建，大幅缩短构建时间
auto-optimise-store = true # ✅ 相同内容链接同一文件，减少重复存储
sandbox-fallback = false # ✅ 始终使用沙盒，失败不重复
EOF
)

prelude() {
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
  check_cmd() {
    command -v "$1" > /dev/null 2>&1
  }
  # 封装长耗时操作
  run_with_progress() {
    local msg="$1"
    shift
    say "开始：$msg"
    if "$@"; then
      say "完成：$msg"
    else
      err "失败：$msg，请检查日志后重试"
    fi
  }


  # 让普通用户以sudo权限执行（显式传递关键环境变量）
  use_sudo(){
    if [ "$IS_ROOT_USER" = false ] && [ "$IS_SUDO_USER" = false ]; then
      # 显式传递 USER、HOME、NIX_CONFIG 等核心变量，解决权限/目录归属问题
      sudo -E \
        USER="$USER_NAME" \
        HOME="$USER_HOME" \
        NIX_CONFIG="${NIX_CONFIG:-}" \
        "$@"  # 加引号，保留参数完整性
    else
      # 已是root/sudo，直接执行（仍显式传递变量确保一致性）
      USER="$USER_NAME" \
      HOME="$USER_HOME" \
      NIX_CONFIG="${NIX_CONFIG:-}" \
      "$@"
    fi
  }
  use_normal(){
    # 1. 先验证普通用户是否存在（安全校验）
    if ! id -u "$USER_NAME" >/dev/null 2>&1; then
      warn "普通用户 $USER_NAME 不存在！"
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
  elevate_privilege(){
    if [ ! -x "$0" ]; then # 如果脚本没有执行权限
      warn "正在赋予脚本执行权限"
      use_sudo chmod +x "$0"
    fi
  }
  # 降级：root/sudo执行时以普通用户重新执行。 -E 保持环境变量不变
  downgrade_privilege(){
    if [ "$EUID" -eq 0 ]; then
      exec sudo -u "$USER_NAME" -E HOME="$USER_HOME" bash "$0" "$@"
    fi
  }
}

check_substituters() {
  say "检测镜像源连通性..."
  local substituter
  for substituter in $USING_SUBSTITUTERS; do
    if curl --head --connect-timeout 5 "$substituter" >/dev/null 2>&1; then
      say "镜像源可用：$substituter"
    else
      warn "镜像源不可用：$substituter，已跳过"
      USING_SUBSTITUTERS=$(echo "$USING_SUBSTITUTERS" | sed "s|$substituter||g")
    fi
  done
  # 确保至少保留官方源
  if ! echo "$USING_SUBSTITUTERS" | grep -q "cache.nixos.org"; then
    USING_SUBSTITUTERS="$USING_SUBSTITUTERS https://cache.nixos.org"
  fi
}
get_architecture() {
  local _ostype _cputype
  _cputype="$(uname -m)"
  OS_TYPE="$(uname -s)"
  if [ "$OS_TYPE" = Linux ]; then
    if [ "$(uname -o)" = Android ]; then
      OS_TYPE=Android
    elif [ -f /etc/os-release ]; then
      source /etc/os-release && [ "${ID:-}" = "nixos" ] && OS_TYPE="NixOS"
    fi
  fi
  if [ "$OS_TYPE" = Darwin ]; then
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
  if [ "$OS_TYPE" = SunOS ]; then
    # 目前 Solaris 和 illumos 系统在执行 `uname -s` 时都会返回 "SunOS"，
    # 因此需要使用 `uname -o` 来区分二者。我们使用系统 uname 命令的完整路径，
    # 以避免用户的 PATH 环境变量中优先存在 coreutils 版本的 uname（该版本历史上曾在此处返回错误值）。
    if [ "$(/usr/bin/uname -o)" = illumos ]; then
      OS_TYPE=illumos
    fi
    # illumos 系统支持多架构用户空间，`uname -m` 命令返回的是机器硬件名称；
    # 例如，在 32 位和 64 位 x86 系统上均返回 "i86pc"。
    # 此处检测运行中的内核所支持的原生（最宽）指令集：
    if [ "$_cputype" = i86pc ]; then
      _cputype="$(isainfo -n)"
    fi
  fi
  case "$OS_TYPE" in
    NixOS) _ostype=linux ;;
    Linux) _ostype=linux ;;
    Darwin) _ostype=darwin ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
  case "$_cputype" in
    aarch64 | arm64) _cputype=aarch64 ;;
    x86_64 | x86-64 | x64 | amd64) _cputype=x86_64 ;;
    *) err "unknown CPU type: $_cputype" ;;
  esac
  ARCH="${_cputype}-${_ostype}"
  say "系统类型：$OS_TYPE"
  say "系统架构：$ARCH"
}
judge_live_cd() {
  IS_LIVE_CD=$([ -f /proc/cmdline ] && grep -qE 'boot=live|live\.iso|nixos-live' /proc/cmdline 2>/dev/null && echo true || { mount | grep -qE ' / .*ro,' 2>/dev/null && [ -f /proc/mounts ] && grep -qE 'iso9660|squashfs' /proc/mounts 2>/dev/null && echo true || { [ -f /proc/mounts ] && grep -qE '/nix/store.*tmpfs|/nix/store.*overlay' /proc/mounts 2>/dev/null && echo true || echo false; }; })
  say "是否为Live CD安装：$IS_LIVE_CD"
}
get_host_name() {
  local host_name
  HOST_NAME=$(hostname)
  if [ "$OS_TYPE" = "NixOS" ] && [ "$IS_LIVE_CD" = true ]; then
    # 自定义主机名
    read -p "请输入自定义主机名（默认$HOST_NAME）： " -r host_name
    HOST_NAME=${host_name:-$HOST_NAME}
  fi
  say "主机名：$HOST_NAME"
}
get_user_name() {
  local user_list user_count choice input_user
  USER_NAME=$(whoami)

  # 获取系统所有真实普通用户（UID≥1000，可登录）
  user_list=()
  while IFS=: read -r username _ uid _ _ home shell; do
    if [[ $uid -ge 1000 && $shell != *"nologin" && $shell != *"/false" ]]; then
      user_list+=("$username")
    fi
  done < /etc/passwd
  user_count=${#user_list[@]}

  # ==============================================
  # 需要手动输入用户名的 3 种情况（统一处理）
  # 1. NixOS LiveCD 环境
  # 2. NixOS 系统 + 当前用户 = nixos
  # ==============================================
  if ([ "$OS_TYPE" = "NixOS" ] && [ "$IS_LIVE_CD" = true ]) || \
     ([ "$OS_TYPE" = "NixOS" ] && [ "$USER_NAME" = "nixos" ]); then

    while true; do
      read -p "请输入用户名：" input_user
      if [[ -n "$input_user" && "$input_user" != "root" ]]; then
        USER_NAME="$input_user"
        break
      else
        echo "❌ 请输入有效的非 root 用户名！"
      fi
    done

  # ==============================================
  # 需要选择用户的情况（修复：必须 ≥2 个用户才选择）
  # 当前是 root + 系统有 两个及以上 普通用户
  # ==============================================
  elif [ "$USER_NAME" = "root" ] && (( user_count >= 2 )); then
    echo -e "\n📋 系统可用用户："
    for i in "${!user_list[@]}"; do
      echo "$((i+1))) ${user_list[$i]}"
    done

    while true; do
      read -p "请选择用户序号：" choice
      if [[ $choice =~ ^[0-9]+$ && $choice -ge 1 && $choice -le $user_count ]]; then
        USER_NAME="${user_list[$((choice-1))]}"
        break
      else
        echo "❌ 输入无效，请输入 1-$user_count"
      fi
    done

  # ==============================================
  # root + 只有 1 个用户 → 自动使用，不提问
  # ==============================================
  elif [ "$USER_NAME" = "root" ] && (( user_count == 1 )); then
    USER_NAME="${user_list[0]}"

  # ==============================================
  # 其他所有情况：全自动，无任何交互
  # ==============================================
  fi

  say "用户名：$USER_NAME"
}
# get_user_name() {
#   local user_name
#   USER_NAME=$(whoami)
#   if [ "$OS_TYPE" = "NixOS" ] && [ "$IS_LIVE_CD" = true ] || [ "$USER_NAME" = "root" ]; then
#     # 循环：直到用户输入 不是 root 的用户名才通过
#     while true; do
#       read -p "请输入用户名（默认$USER_NAME）： " -r user_name
#       # 如果用户直接回车，使用默认值
#       USER_NAME=${user_name:-$USER_NAME}

#       # 判断：如果是 root，强制重新输入
#       if [ "$USER_NAME" = "root" ]; then
#         echo "❌ 错误：不能使用 root 作为用户名，请重新输入！"
#       else
#         # 输入合法，退出循环
#         break
#       fi
#     done
#   fi
#   say "用户名：$USER_NAME"
# }
init(){
  prelude
  elevate_privilege
  get_architecture
  judge_live_cd
  get_host_name
  get_user_name
  # check_substituters
}
# 安全的用户输入选择函数
install_type_choice() {
  local choice
  while true; do
    read -p "请选择安装类型：(1. 单用户安装 2. 多用户安装，默认1) " -r choice
    choice=${choice:-1} # 默认值
    if [[ "$choice" =~ ^[12]$ ]]; then
      break
    else
      warn "无效输入，请输入1或2"
    fi
  done
  case "$choice" in
    1) single_nix_install ;;
    2) multi_nix_install ;;
  esac
}

program_install() {
  local pkg="$1"
  [ -z "$pkg" ] && return 0

  case "$OS_TYPE" in
    NixOS)
      use_sudo nix --option substituters "$USING_SUBSTITUTERS" profile add "nixpkgs#$pkg"
      ;;
    Linux)
      local install_cmd=""
      check_cmd oma && install_cmd="oma install -y"
      check_cmd apt && install_cmd="apt install -y"
      check_cmd yum && install_cmd="yum install -y"
      check_cmd dnf && install_cmd="dnf install -y"
      check_cmd apk && install_cmd="apk install -y"
      check_cmd pacman && install_cmd="pacman -S --noconfirm"
      check_cmd zypper && install_cmd="zypper install -y"

      if [ "$pkg" = "xz" ]; then
        if [[ "$install_cmd" == *apt* || "$install_cmd" == *oma* ]]; then
          pkg="xz-utils"
        fi
      fi

      [ -n "$install_cmd" ] && use_sudo $install_cmd "$pkg"
      ;;
    Darwin)
      brew install "$pkg"
      ;;
  esac
}

pre_program_install() {
  local target_program=()

  case "$OS_TYPE" in
    NixOS)
      return 0
      ;;
    Linux)
      target_program=("curl" "xz" "git" "pciutils")
      ;;
    Darwin)
      return 0
      ;;
    *)
      err "unrecognized OS type: $OS_TYPE"
      ;;
  esac

  # 批量安装
  for pkg in "${target_program[@]}"; do
    # 检查命令是否存在（原逻辑）
    case "$pkg" in
      curl)     check_cmd "curl" || { warn "curl 不存在，开始安装"; program_install "$pkg"; } ;;
      xz)       check_cmd "xz" || { warn "xz 不存在，开始安装"; program_install "$pkg"; } ;;
      git)      check_cmd "git" || { warn "git 不存在，开始安装"; program_install "$pkg"; } ;;
      pciutils) check_cmd "lspci" || { warn "lspci 不存在，开始安装"; program_install "$pkg"; } ;;
      disko)      check_cmd "disko" || { warn "disko 不存在，开始安装"; program_install "$pkg"; } ;;
    esac
  done

  echo "已安装前置软件"
}
single_nix_install(){
  case "$OS_TYPE" in
    NixOS) return 0 ;;
    Linux)
      bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add
      IS_SINGLE_USER_INSTALLED=true
      ;;
    Darwin) return 0 ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
}
multi_nix_install(){
  case "$OS_TYPE" in
    NixOS) return 0 ;;
    Linux)
      NIX_INSTALLER_YES=1 bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add --daemon
      IS_MULTI_USER_INSTALLED=true
      ;;
    Darwin) return 0 ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
}
is_single_nix_installed(){
  case "$OS_TYPE" in
    NixOS) return 0 ;;
    Linux)
      if [ -f /home/$USER_NAME/.nix-profile/etc/profile.d/nix.sh ]; then # 单用户安装
        return 1;
      else
        return 0;
      fi
      ;;
    Darwin) return 0 ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
}
is_multi_nix_installed(){
  case "$OS_TYPE" in
    NixOS) return 0 ;;
    Linux)
      if [ -f /home/$USER_NAME/.nix-profile/etc/profile.d/nix.sh ]; then # 单用户安装
        return 1;
      else
        return 0;
      fi
      ;;
    Darwin) return 0 ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
}
choose_install_nix_type(){
  case "$OS_TYPE" in
    NixOS)
      ;; # NixOS 不需要安装 Nix
    Linux)
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
    Darwin) return 0 ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
}
source_nix_profile(){
  case "$OS_TYPE" in
    NixOS) return 0 ;;
    Linux)
      if is_multi_nix_installed; then # 多用户安装
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      elif is_single_nix_installed; then # 单用户安装
        source /home/$USER_NAME/.nix-profile/etc/profile.d/nix.sh
      fi
      ;;
    Darwin) return 0 ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
}
check_nix_install(){
  case "$OS_TYPE" in
    NixOS) return 0 ;;
    Linux)
      if is_multi_nix_installed; then # 多用户安装
        echo "已安装nix (多用户模式)"
        source_nix_profile
      elif is_single_nix_installed; then # 单用户安装
        if [ "$IS_ROOT_USER" = true ] || [ "$IS_SUDO_USER" = true ]; then
          warn "正在以普通用户重新执行脚本，单用户需要以普通用户执行"
          downgrade_privilege
        fi
        echo "已安装nix (单用户模式)"
        source_nix_profile
      else
        warn "nix command not found"
        choose_install_nix_type
      fi
      ;;
    Darwin) return 0 ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
}
nix_install(){
  case "$OS_TYPE" in
    NixOS)
      if is_multi_nix_installed; then # 多用户安装
        echo "已安装nix (多用户模式)"
        source_nix_profile
      elif is_single_nix_installed; then # 单用户安装
        if [ "$IS_ROOT_USER" = true ] || [ "$IS_SUDO_USER" = true ]; then
          warn "正在以普通用户重新执行脚本，单用户需要以普通用户执行"
          downgrade_privilege
        fi
        echo "已安装nix (单用户模式)"
        source_nix_profile
      else
        warn "nix command not found"
        choose_install_nix_type
      fi
      ;;
    Linux) check_nix_install ;;
    Darwin) return 0 ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
}

nix_config(){
  case "$OS_TYPE" in
    NixOS)
      local _nixpkg
      for _nixpkg in "$BINARY_URL"; do
        use_normal nix registry add nixpkgs $_nixpkg
        use_sudo nix registry add nixpkgs $_nixpkg
      done
      ;;
    Linux) check_nix_install ;;
    Darwin) return 0 ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
}

flake_apply_choice(){
  case "$OS_TYPE" in
    NixOS)
      read -p "应用flake配置？(Y/N，默认Y) " -r
      if [[ $REPLY =~ ^[Yy]$ ]] || [ -z $REPLY ]; then # (Y/N，默认Y)
        say "应用flake配置..."
      else
        say "不应用flake配置..."
        exit 0
      fi
      : # 无操作，NixOS默认应用flake配置
      ;;
    Linux)
      read -p "应用flake配置？(Y/N，默认Y) " -r
      if [[ $REPLY =~ ^[Yy]$ ]] || [ -z $REPLY ]; then # (Y/N，默认Y)
        say "应用flake配置..."
      else
        say "不应用flake配置..."
        exit 0
      fi
      ;;
    Darwin) return 0 ;;
    *) err "unrecognized OS type: $OS_TYPE" ;;
  esac
}

cpu_detect(){
  nix run nixpkgs#fastfetch
}

main(){
  init
  run_with_progress "安装前置软件" pre_program_install
  run_with_progress "检查Nix" nix_install
  run_with_progress "配置Nix" nix_config

  flake_apply_choice

  cpu_detect
  gpu_detect
  disk_detect
  hardware_generate
  flake_generate
  flake_copy
  flake_apply
}

main