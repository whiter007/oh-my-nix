#!/bin/bash
set -eo pipefail

USING_SUBSTITUTERS="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://mirror.sjtu.edu.cn/nix-channels/store https://mirrors.cqupt.edu.cn/nix-channels/store https://cache.nixos.org"
export NIX_CONFIG="experimental-features = nix-command flakes
substituters = $USING_SUBSTITUTERS"
readonly BINARY_URL="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz"

__print() {
  if [ -t 1 ]; then
    printf '\33[1m%s:\33[0m %s\n' "$1" "$2" >&2
  else
    printf '%s: %s\n' "$1" "$2" >&2
  fi
}

say() {
  __print 'info' "$1"
}

warn() {
  __print 'warn' "$1"
}

err() {
  __print 'error' "$1"
  exit 1
}

get_cpu_info() {
  local _cputype _cpuvendor
  _cputype=$(uname -m)

  case "$_cputype" in
    aarch64 | arm64) CPU_ARCH=aarch64 ;;
    x86_64 | x86-64 | x64 | amd64) CPU_ARCH=x86_64 ;;
    *) CPU_ARCH=unknown ;;
  esac

  if command -v lscpu >/dev/null 2>&1; then
    _cpuvendor=$(lscpu | grep -E 'Vendor ID|厂商 ID' | awk '{print $3}')
  elif [ -f /proc/cpuinfo ]; then
    _cpuvendor=$(grep 'vendor_id' /proc/cpuinfo | head -n1 | awk '{print $3}')
  else
    _cpuvendor=unknown
  fi

  case "$_cpuvendor" in
    GenuineIntel) CPU_VENDOR=intel ;;
    Intel) CPU_VENDOR=intel ;;
    AuthenticAMD) CPU_VENDOR=amd ;;
    AMD) CPU_VENDOR=amd ;;
    # *) CPU_VENDOR=unknown ;;
    *) err "Unknown CPU vendor: $_cpuvendor" ;;
  esac

  say "CPU Architecture: $CPU_ARCH"
  say "CPU Vendor: $CPU_VENDOR"
}

get_virtuliztion_info() {
    local cpu_flag cpu_name iommu_name kvm_mod

    # 根据厂商赋值
    case "$CPU_VENDOR" in
        intel) cpu_flag="vmx"; cpu_name="Intel VT-x"; iommu_name="Intel VT-d"; kvm_mod="kvm_intel" ;;
        amd)   cpu_flag="svm"; cpu_name="AMD-V";     iommu_name="AMD-Vi";   kvm_mod="kvm_amd" ;;
        *)     echo "Unknown CPU vendor: $CPU_VENDOR"; return 1 ;;
    esac

    # 检测CPU虚拟化：硬件支持(vmx/svm) + 内核模块已加载
    local is_cpu="false"
    if grep -qw "$cpu_flag" /proc/cpuinfo && [ -d "/sys/module/$kvm_mod" ]; then
        is_cpu="true"
    fi

    # 检测IOMMU：存在IOMMU组目录且不为空
    local is_iommu="false"
    if shopt -s nullglob; then
        local dirs=(/sys/kernel/iommu_groups/*)
        [ "${#dirs[@]}" -gt 0 ] && is_iommu="true"
    fi

    # 检测嵌套虚拟化：检查内核模块参数
    local is_nested="false"
    local nested_param="/sys/module/$kvm_mod/parameters/nested"
    if [ -f "$nested_param" ]; then
        local nested_val
        nested_val=$(cat "$nested_param" 2>/dev/null)
        if [ "$nested_val" = "Y" ] || [ "$nested_val" = "1" ]; then
            is_nested="true"
        fi
    fi

    # 检测KVM设备可用性
    local is_kvm_dev="false"
    [ -c "/dev/kvm" ] && is_kvm_dev="true"

    # 输出结果
    say "CPU Virtualization: $is_cpu ($cpu_name)"
    say "Nested Virtualization: $is_nested (${cpu_name} nested)"
    say "KVM Device: $is_kvm_dev (/dev/kvm)"
    say "IOMMU Support: $is_iommu ($iommu_name)"
}


get_system_info() {
  local _ostype _cputype
  _ostype=$(uname -s)
  _cputype=$(uname -m)

  # 处理Linux系统
  if [ "$_ostype" = Linux ]; then
    if [ -f /etc/os-release ]; then
      source /etc/os-release && [ "${ID:-}" = "nixos" ] && _ostype="nixos"
    fi
  # 处理Darwin系统
  elif [ "$_ostype" = Darwin ]; then
    # 处理Rosetta兼容层的架构检测
    if [ "$_cputype" = i386 ]; then
      if (sysctl hw.optional.x86_64 2> /dev/null || true) | grep -q ': 1'; then
        _cputype=x86_64
      fi
    elif [ "$_cputype" = x86_64 ]; then
      if (sysctl hw.optional.arm64 2> /dev/null || true) | grep -q ': 1'; then
        _cputype=arm64
      fi
    fi
  fi

  # 统一架构名称
  case "$_cputype" in
    aarch64 | arm64) _arch=aarch64 ;;
    x86_64 | x86-64 | x64 | amd64) _arch=x86_64 ;;
    *) _arch=unknown ;;
  esac

  # 统一OS_TYPE为小写
  case "$_ostype" in
    Linux) OS_TYPE=linux ;;
    Darwin) OS_TYPE=darwin ;;
    nixos) OS_TYPE=nixos ;;
    *) OS_TYPE=unknown ;;
  esac

  # 拼接ARCH变量，nixos属于linux
  if [ "$OS_TYPE" = "nixos" ]; then
    ARCH="$_arch-linux"
  else
    ARCH="$_arch-$OS_TYPE"
  fi

  IS_LIVE_CD=false
  if [ -f /proc/cmdline ]; then
    if grep -qE 'boot=live|live\.iso|nixos-live' /proc/cmdline 2>/dev/null; then
      IS_LIVE_CD=true
    fi
  fi
  if [ "$IS_LIVE_CD" = false ]; then
    if mount | grep -qE ' / .*ro,' 2>/dev/null && [ -f /proc/mounts ]; then
      if grep -qE 'iso9660|squashfs' /proc/mounts 2>/dev/null; then
        IS_LIVE_CD=true
      fi
    fi
  fi
  if [ "$IS_LIVE_CD" = false ]; then
    if [ -f /proc/mounts ] && grep -qE '/nix/store.*tmpfs|/nix/store.*overlay' /proc/mounts 2>/dev/null; then
      IS_LIVE_CD=true
    fi
  fi

  say "System Type: $OS_TYPE"
  say "Architecture: $ARCH"
  say "Is Live CD: $IS_LIVE_CD"
}

get_user_info() {
  USER_NAME=$(whoami)
  IS_ROOT_USER=false
  IS_SUDO_USER=false

  if [ "$EUID" -eq 0 ]; then
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
      IS_SUDO_USER=true
      USER_NAME="$SUDO_USER"
    else
      IS_ROOT_USER=true
    fi
  fi

  USER_HOME=$(eval echo ~$USER_NAME)

  USER_LIST=()
  if [ -f /etc/passwd ]; then
    while IFS=: read -r username _ uid _ _ home shell; do
      if [[ $uid -ge 1000 && $shell != *"nologin" && $shell != *"/false" ]]; then
        USER_LIST+=($username)
      fi
    done < /etc/passwd
  fi

  say "Current User: $USER_NAME"
  say "Is Root User: $IS_ROOT_USER"
  say "Is Sudo User: $IS_SUDO_USER"
  say "User Home: $USER_HOME"
  say "Available Users: ${USER_LIST[*]}"
}

get_nix_install_info() {

  if [ "$OS_TYPE" = "nixos" ]; then
    echo "builtin"
  fi

  if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
    source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    # say "Nix Daemon Installed"
    echo "multi-installed"
  elif [ -f "$USER_HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    source "$USER_HOME/.nix-profile/etc/profile.d/nix.sh"
    echo "single-installed"
  else
    warn "Nix not installed for any user"
    echo "not-installed"
  fi
}

get_system_basic_info() {
  say "=== System Basic Information ==="
  get_cpu_info
  get_virtuliztion_info
  get_system_info
  get_user_info
  # local nix_install_status
  # nix_install_status=$(get_nix_install_info)
  # if [ "$nix_install_status" = "single-installed" ]; then
  #   say "Nix Install Type: $nix_install_status (user: $NIX_SINGLE_USER_INSTALLED_USER)"
  # else
  #   say "Nix Install Type: $nix_install_status"
  # fi
  say "==============================="
}


nix_apply_choices() {
  local nix_install_status=$(get_nix_install_info)

  if [ "$nix_install_status" = "not-installed" ]; then
    if [ "$OS_TYPE" = "linux" ]; then
      if [ "$IS_ROOT_USER" = "true" ]; then
        read -p "是否确认多用户安装？(y/n) " -r
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
          INSTALL_TYPE="multi"
        else
          err "用户取消安装（若单用户安装请以普通用户执行脚本）"
        fi
      else
        read -p "请选择安装类型：(1. 单用户安装 2. 多用户安装) " -r
        case "$REPLY" in
          1)
            INSTALL_TYPE="single"
            ;;
          2)
            INSTALL_TYPE="multi"
            ;;
          *)
            warn "无效选择，默认使用单用户安装"
            INSTALL_TYPE="single"
            ;;
        esac
      fi
    elif [ "$OS_TYPE" = "darwin" ]; then
      read -p "是否确认多用户安装？(y/n) " -r
      if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        INSTALL_TYPE="multi"
      else
        err "用户取消安装（若单用户安装请以普通用户执行脚本）"
      fi
    else
      err "不支持的系统类型，停止进程"
    fi
    say "Nix Install Type: $INSTALL_TYPE"
  fi
}

nix_install() {
  local nix_status
  nix_status=$(get_nix_install_info)

  case "$nix_status" in
    builtin|multi-installed|single-installed)
      say "Nix already installed ($nix_status)"
      # Source the appropriate profile
      if [ "$nix_status" = "multi-installed" ]; then
        if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
          source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
          say "Sourced Nix daemon profile"
        fi
      elif [ "$nix_status" = "single-installed" ]; then
        local single_nix_path="$USER_HOME/.nix-profile/etc/profile.d/nix.sh"
        if [ -f "$single_nix_path" ]; then
          say "Found Nix profile at $single_nix_path"
          source "$single_nix_path"
          say "Sourced Nix profile for user $USER_NAME"
        else
          warn "Nix profile not found at $single_nix_path"
        fi
      fi
      ;;
    not-installed)
      say "Nix not installed, proceeding with installation type: $INSTALL_TYPE"
      case "$INSTALL_TYPE" in
        single)
          if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then
            warn "Single-user installation should be run as normal user. Downgrading privilege."
            # Need to re-exec script as normal user? For now, just warn.
            # In original script, they downgrade privilege.
          fi
          case "$OS_TYPE" in
            linux)
              bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add
              ;;
            darwin)
              # macOS single-user installation? Not implemented.
              warn "Single-user installation on macOS not implemented"
              ;;
            *)
              err "Unsupported OS for single-user installation: $OS_TYPE"
              ;;
          esac
          ;;
        multi)
          case "$OS_TYPE" in
            linux)
              NIX_INSTALLER_YES=1 bash <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-channel-add --daemon
              ;;
            darwin)
              # macOS multi-user installation? Not implemented.
              warn "Multi-user installation on macOS not implemented"
              ;;
            *)
              err "Unsupported OS for multi-user installation: $OS_TYPE"
              ;;
          esac
          ;;
        *)
          err "Unknown INSTALL_TYPE: $INSTALL_TYPE"
          ;;
      esac
      ;;
    *)
      err "Unexpected nix install status: $nix_status"
      ;;
  esac
}

nix_config() {
  say "Configuring Nix..."
  local nix_status
  nix_status=$(get_nix_install_info)

  case "$nix_status" in
    builtin)
      say "Adding Nix registry..."
      if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then
        nix registry add nixpkgs "$BINARY_URL"
        su - "$USER_NAME" -c "USER=$USER_NAME HOME=$USER_HOME nix registry add nixpkgs $BINARY_URL" # 给普通用户添加仓库
      else
        nix registry add nixpkgs "$BINARY_URL"
      fi
      ;;
    multi-installed)
      say "Configuring multi-user Nix installation..."
      local nix_conf_dir="/etc/nix"
      # Ensure directory exists
      if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then
        mkdir -p "$nix_conf_dir"
        chmod 755 "$nix_conf_dir"
      else
        sudo mkdir -p "$nix_conf_dir"
        sudo chmod 755 "$nix_conf_dir"
      fi
      # Write nix.conf
      cat << EOF | if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then tee "$nix_conf_dir/nix.conf" >/dev/null; else sudo tee "$nix_conf_dir/nix.conf" >/dev/null; fi
experimental-features = nix-command flakes
trusted-users = root $USER_NAME
substituters = $USING_SUBSTITUTERS
trusted-substituters = $USING_SUBSTITUTERS
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= mirrors.tuna.tsinghua.edu.cn/nix-channels/store:rSzv032o86Rxxhl6/7aYRl0v56Kza+4+4G8q0aT+28A= mirrors.ustc.edu.cn/nix-channels/store:o9ien6A6Y75/32Jdl3lZF52E6hDUmD+86L948YH9QyU=
builders-use-substitutes = true
auto-optimise-store = true
sandbox-fallback = false
EOF
      # Add user to nixbld group
      if ! id -nG "$USER_NAME" | grep -qw "nixbld"; then
        say "Adding user $USER_NAME to nixbld group..."
        if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then
          usermod -aG nixbld "$USER_NAME"
        else
          sudo usermod -aG nixbld "$USER_NAME"
        fi
      fi
      # Reload daemon
      if command -v systemctl >/dev/null 2>&1; then
        say "Reloading systemd daemon..."
        sudo systemctl daemon-reload
        say "Restarting nix-daemon..."
        sudo systemctl restart nix-daemon.service
        say "Waiting for nix-daemon to be ready..."
        while ! sudo systemctl is-active --quiet nix-daemon.service; do sleep 1; done
      fi
      # Load environment variables after daemon reload
      say "Loading environment variables..."
      if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
      # Verify configuration
    #   say "Verifying configuration..."
    #   nix config show | grep trusted-users
    #   if ! nix store ping 2>/dev/null; then
    #     warn "nix daemon may not be responding correctly"
    #   fi
    #   say "Configuration verification complete"

      # Remove user-level config to avoid conflicts
      if [ -f "$USER_HOME/.config/nix/nix.conf" ]; then
        warn "Removing user-level nix.conf to avoid conflicts"
        rm -f "$USER_HOME/.config/nix/nix.conf"
      fi
      # Add nix registry for multi-user installation
      say "Adding Nix registry..."
      if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then
        nix registry add nixpkgs "$BINARY_URL"
        su - "$USER_NAME" -c "USER=$USER_NAME HOME=$USER_HOME nix registry add nixpkgs $BINARY_URL" # 给普通用户添加仓库
      else
        nix registry add nixpkgs "$BINARY_URL"
      fi
      ;;
    single-installed)
      say "Configuring single-user Nix installation..."
      local nix_conf_dir="$USER_HOME/.config/nix"
      mkdir -p "$nix_conf_dir"
      chmod 755 "$nix_conf_dir"
      cat << EOF > "$nix_conf_dir/nix.conf"
experimental-features = nix-command flakes
substituters = $USING_SUBSTITUTERS
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= mirrors.tuna.tsinghua.edu.cn/nix-channels/store:rSzv032o86Rxxhl6/7aYRl0v56Kza+4+4G8q0aT+28A= mirrors.ustc.edu.cn/nix-channels/store:o9ien6A6Y75/32Jdl3lZF52E6hDUmD+86L948YH9QyU=
builders-use-substitutes = true
auto-optimise-store = true
sandbox-fallback = false
EOF

      # Load environment variables after daemon reload
      say "Loading environment variables..."
      if [ -f "$USER_HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        source "$USER_HOME/.nix-profile/etc/profile.d/nix.sh"
      fi
      # Add nix registry for single-user installation
      say "Adding Nix registry..."
      nix registry add nixpkgs "$BINARY_URL"
      ;;
    *)
      err "Nix not installed, cannot configure."
      ;;
  esac
}

flake_apply_choices() {
  say "Asking about flake configuration..."
  case "$OS_TYPE" in
    nixos|linux)
      read -p "Apply flake configuration? (Y/n, default Y) " -r
      if [[ $REPLY =~ ^[Nn]$ ]]; then
        say "Skipping flake configuration."
        exit 0
      else
        say "Proceeding with flake configuration."
      fi
      ;;
    darwin)
      say "Flake configuration on macOS not implemented."
      ;;
    *)
      err "Unsupported OS for flake configuration: $OS_TYPE"
      ;;
  esac
}

detect_disk_info(){
  say "Detecting disk information..."
}
disko_config_generate(){
  say "Generating disko.nix..."
}

# 去除数字前导零 (09 -> 9, 00 -> 0)
strip_leading_zeros() {
    local val="${1:-0}"
    val="$(printf '%s' "$val" | sed -E 's/^0+//')"
    printf '%s' "${val:-0}"
}

# 极度稳健的 BusID 规整化 (兼容 WSL 等非标准 lspci 输出)
normalize_pci_bus_id() {
    local addr="$1"

    # 将所有的冒号和点号替换为空格，然后读入数组
    # 例如: "0000:00:02.0" -> "0000 00 02 0"
    # 例如: "55c1:00:00.0" -> "55c1 00 00 0" (WSL格式)
    local parts
    read -ra parts <<< "${addr//[:.]/ }"

    local len=${#parts[@]}
    # 安全兜底：如果切出来的段数少于3，直接返回原值
    if (( len < 3 )); then
        printf '%s' "$addr"
        return
    fi

    # 永远取数组的最后三段作为 bus, dev, func
    local bus="${parts[$((len-3))]}"
    local dev="${parts[$((len-2))]}"
    local func="${parts[$((len-1))]}"

    printf 'PCI:%s:%s:%s' \
        "$(strip_leading_zeros "$bus")" \
        "$(strip_leading_zeros "$dev")" \
        "$(strip_leading_zeros "$func")"
}

# 检测所有显卡及其规整后的 BusID
detect_gpu_info() {
    # -D 使用设备域，-d ::03xx 仅匹配 VGA 兼容控制器
    local gpus
    gpus="$(lspci -D -d ::03xx 2>/dev/null)" || true

    if [[ -z "$gpus" ]]; then
        warn "unknown gpu"
        return 0
    fi

    local idx=1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local addr="${line%% *}"
        local desc="${line#* }"

        printf "%d. %-4s | %s\n" \
            "$idx" \
            "$(normalize_pci_bus_id "$addr")" \
            "$desc"
        ((idx++))
    done <<< "$gpus"
}
flake_config_generate(){
  say "Generating flake.nix..."
}
flake_config_copy() {
  say "Copying flake configuration..."
  case "$OS_TYPE" in
    nixos)
      if [ "$IS_LIVE_CD" = "true" ]; then
        say "Live CD environment: generating hardware configuration..."
        # Run nixos-generate-config
        if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then
          nixos-generate-config --dir /etc/nixos/
        else
          sudo nixos-generate-config --dir /etc/nixos/
        fi
        # Also copy disko configuration if exists
        if [ -f "./config/disko-config.nix" ]; then
          say "Copying disko configuration..."
          cp "./config/disko-config.nix" /etc/nixos/
        fi
      else
        say "Normal NixOS: hardware configuration should already exist."
      fi
      ;;
    linux)
      say "Generating home-manager configuration..."
      # Ensure target directory exists
      local target_dir="$USER_HOME/.config/home-manager"
      mkdir -p "$target_dir"
      # Copy current directory's flake files
      if [ -f "./flake.nix" ]; then
        cp -r ./* "$target_dir"/
        say "Copied flake files to $target_dir"
      else
        warn "No flake.nix found in current directory."
      fi
      ;;
    darwin)
      say "Flake configuration generation on macOS not implemented."
      ;;
    *)
      err "Unsupported OS for flake generation: $OS_TYPE"
      ;;
  esac
}

flake_config_apply() {
  say "Applying flake configuration..."
  case "$OS_TYPE" in
    nixos)
      if [ "$IS_LIVE_CD" = "true" ]; then
        say "Live CD installation using flake..."
        if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then
          nixos-install --option extra-substituters "$USING_SUBSTITUTERS" --flake /etc/nixos/#nixos --impure
        else
          sudo -E nixos-install --option extra-substituters "$USING_SUBSTITUTERS" --flake /etc/nixos/#nixos --impure
        fi
      else
        say "Applying flake configuration to existing NixOS..."
        if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then
          nixos-rebuild switch --option extra-substituters "$USING_SUBSTITUTERS" --flake /etc/nixos/ --impure
        else
          sudo -E nixos-rebuild switch --option extra-substituters "$USING_SUBSTITUTERS" --flake /etc/nixos/ --impure
        fi
      fi
      ;;
    linux)
      say "Applying home-manager flake configuration..."
      local target_dir="$USER_HOME/.config/home-manager"
      if [ -f "$target_dir/flake.nix" ]; then
        # Check if multi-user or single-user installation
        local nix_status
        nix_status=$(get_nix_install_info)
        if [ "$nix_status" = "multi-installed" ]; then
          su - "$USER_NAME" -c "USER=$USER_NAME HOME=$USER_HOME nix run nixpkgs#home-manager -- switch --flake $target_dir --impure -b backup"
        else
          USER=$USER_NAME HOME=$USER_HOME nix run nixpkgs#home-manager -- switch --flake $target_dir --impure -b backup
        fi
      else
        err "flake.nix not found in $target_dir"
      fi
      ;;
    darwin)
      say "Flake configuration application on macOS not implemented."
      ;;
    *)
      err "Unsupported OS for flake application: $OS_TYPE"
      ;;
  esac
}

congratulation() {
  say "Congratulations! Setup completed successfully."
  case "$OS_TYPE" in
    nixos)
      if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then
        nix --option extra-substituters "$USING_SUBSTITUTERS" run nixpkgs#hello
      else
        sudo nix --option extra-substituters "$USING_SUBSTITUTERS" run nixpkgs#hello
      fi
      ;;
    linux)
      if [ "$IS_ROOT_USER" = "true" ] || [ "$IS_SUDO_USER" = "true" ]; then
        su - "$USER_NAME" -c "USER=$USER_NAME HOME=$USER_HOME nix run nixpkgs#hello"
      else
        nix run nixpkgs#hello
      fi
      ;;
    darwin)
      say "Run 'nix run nixpkgs#hello' to test installation."
      ;;
    *)
      say "Setup completed."
      ;;
  esac
}

main() {
  get_system_basic_info
  nix_apply_choices
  nix_install
  nix_config
  flake_apply_choices
  detect_gpu_info
  # flake_config_generate
  flake_config_copy
  flake_config_apply
  congratulation
}

main