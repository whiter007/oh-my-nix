#!/usr/bin/env bash
set -euo pipefail
# ==============================================================================
# Professional Nix One-Click Deployment Script
# Supports: NixOS, Generic Linux, macOS (Darwin)
# Features: Auto-detect, Privilege Elevation/Demotion, Nix Install, Flake Apply
# ==============================================================================
# ------------------------------------------------------------------------------
# Global Configuration & Constants
# ------------------------------------------------------------------------------
readonly NIX_SUBSTITUTERS="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://mirror.sjtu.edu.cn/nix-channels/store https://mirrors.cqupt.edu.cn/nix-channels/store https://cache.nixos.org"
readonly NIX_TRUSTED_PUBLIC_KEYS="cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= mirrors.tuna.tsinghua.edu.cn/nix-channels/store:rSzv032o86Rxxhl6/7aYRl0v56Kza+4+4G8q0aT+28A= mirrors.ustc.edu.cn/nix-channels/store:o9ien6A6Y75/32Jdl3lZF52E6hDUmD+86L948YH9QyU="
readonly NIXPKGS_URL="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz"
readonly NIX_INSTALLER_URL="https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install"
readonly DISKO_FILE_PATH="./config/disko-config.nix"
# Force substituters and flakes for current script execution process
export NIX_CONFIG="experimental-features = nix-command flakes
substituters = ${NIX_SUBSTITUTERS}
trusted-substituters = ${NIX_SUBSTITUTERS}
trusted-public-keys = ${NIX_TRUSTED_PUBLIC_KEYS}"
# Global State Variables
OS_TYPE=""
ARCH=""
IS_LIVE_CD=false
USER_NAME=""
USER_HOME=""
IS_ROOT_USER=false
IS_SUDO_USER=false
NIX_STATUS="" # builtin, multi-installed, single-installed, not-installed
# ------------------------------------------------------------------------------
# Utility Functions
# ------------------------------------------------------------------------------
__print() {
    local level="$1"; shift
    local color=""
    case "$level" in
        info) color='\033[1;34m' ;; warn) color='\033[1;33m' ;; error) color='\033[1;31m' ;; success) color='\033[1;32m' ;;
    esac
    if [ -t 1 ]; then printf "${color}[%s]\033[0m %s\n" "$level" "$*" >&2
    else printf "[%s] %s\n" "$level" "$*" >&2; fi
}
say() { __print info "$@"; }
warn() { __print warn "$@"; }
err() { __print error "$@"; exit 1; }
success() { __print success "$@"; }
check_cmd() { command -v "$1" > /dev/null 2>&1; }
need_cmd() { if ! check_cmd "$1"; then err "Required command '$1' not found."; fi; }
# Run command as root. Forces PATH to prevent 'command not found' after sudo.
run_as_root() {
    if [ "$EUID" -ne 0 ]; then
        sudo env PATH="$PATH" USER="$USER_NAME" HOME="$USER_HOME" NIX_CONFIG="${NIX_CONFIG:-}" "$@"
    else
        env PATH="$PATH" USER="$USER_NAME" HOME="$USER_HOME" NIX_CONFIG="${NIX_CONFIG:-}" "$@"
    fi
}
# Run command as the target normal user. Uses `sudo -u` to completely switch context,
# which prevents Nix from complaining about $HOME ownership when run via root/sudo.
run_as_user() {
    if [ "$EUID" -eq 0 ]; then
        sudo -u "$USER_NAME" env PATH="$PATH" USER="$USER_NAME" HOME="$USER_HOME" NIX_CONFIG="${NIX_CONFIG:-}" "$@"
    else
        env PATH="$PATH" USER="$USER_NAME" HOME="$USER_HOME" NIX_CONFIG="${NIX_CONFIG:-}" "$@"
    fi
}
# ------------------------------------------------------------------------------
# System Initialization & Detection
# ------------------------------------------------------------------------------
get_system_info() {
    say "Detecting system information..."
    local _ostype _cputype
    _ostype="$(uname -s)"
    _cputype="$(uname -m)"
    # Darwin Rosetta handling
    if [ "$_ostype" = Darwin ]; then
        if [ "$_cputype" = i386 ]; then
            (sysctl hw.optional.x86_64 2>/dev/null || true) | grep -q ': 1' && _cputype=x86_64
        elif [ "$_cputype" = x86_64 ]; then
            (sysctl hw.optional.arm64 2>/dev/null || true) | grep -q ': 1' && _cputype=arm64
        fi
    fi
    case "$_cputype" in
        aarch64|arm64) ARCH=aarch64 ;;
        x86_64|x86-64|x64|amd64) ARCH=x86_64 ;;
        *) err "Unsupported CPU architecture: $_cputype" ;;
    esac
    case "$_ostype" in
        Linux)
            OS_TYPE=linux
            [ -f /etc/os-release ] && source /etc/os-release
            [ "${ID:-}" = "nixos" ] && OS_TYPE=nixos
            # Live CD Detection
            if [ -f /proc/cmdline ] && grep -qE 'boot=live|live\.iso|nixos-live' /proc/cmdline 2>/dev/null; then
                IS_LIVE_CD=true
            elif [ -f /proc/mounts ] && grep -qE '/nix/store.*(tmpfs|overlay)' /proc/mounts 2>/dev/null; then
                IS_LIVE_CD=true
            fi
            ;;
        Darwin) OS_TYPE=darwin ;;
        *) err "Unsupported OS: $_ostype" ;;
    esac
    # User Context
    USER_NAME=$(whoami)
    IS_ROOT_USER=false
    IS_SUDO_USER=false
    if [ "$EUID" -eq 0 ]; then
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            IS_SUDO_USER=true
            USER_NAME="$SUDO_USER"
        else
            IS_ROOT_USER=true
            # Fallback to first normal user if executed by raw root
            USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || awk -F: '$3>=1000 && $1!="nobody"{print $1;exit}' /etc/passwd)}"
        fi
    fi
    USER_HOME=$(eval echo "~$USER_NAME")
    say "OS: $OS_TYPE | Arch: $ARCH | User: $USER_NAME | Root: $IS_ROOT_USER | Sudo: $IS_SUDO_USER | LiveCD: $IS_LIVE_CD"
}
# ------------------------------------------------------------------------------
# Pre-program Dependencies
# ------------------------------------------------------------------------------
pre_program_install() {
    say "Checking required tools..."
    case "$OS_TYPE" in
        nixos)
            check_cmd git || run_as_root nix profile add nixpkgs#git
            check_cmd lspci || run_as_root nix profile add nixpkgs#pciutils
            ;;
        linux)
            local tools="curl:curl xz:xz|xz-utils git:git lspci:pciutils"
            local pkgs=() pm="" install_cmd=""
            for item in $tools; do
                cmd=${item%%:*} pkg=${item#*:}
                check_cmd "$cmd" || pkgs+=(${pkg%|*})
            done
            [ ${#pkgs[@]} -eq 0 ] && { say "All required tools are installed."; return 0; }
            warn "Missing tools: ${pkgs[*]}"
            check_cmd oma && pm="oma" && install_cmd="oma install -y"
            check_cmd apt && pm="apt" && install_cmd="apt install -y"
            check_cmd dnf && pm="dnf" && install_cmd="dnf install -y"
            check_cmd yum && pm="yum" && install_cmd="yum install -y"
            check_cmd pacman && pm="pacman" && install_cmd="pacman -S --noconfirm"
            check_cmd zypper && pm="zypper" && install_cmd="zypper install -y"
            [ "$pm" = "apt" ] && pkgs=(${pkgs[@]/xz/xz-utils})
            [ "$pm" = "oma" ] && echo "Tip: Run 'oma mirror' first if download is slow."
            if [ -n "$install_cmd" ]; then
                run_as_root $install_cmd "${pkgs[@]}"
            else
                err "No supported package manager found. Please install manually: ${pkgs[*]}"
            fi
            ;;
        darwin)
            need_cmd git
            need_cmd curl
            ;;
    esac
}
# ------------------------------------------------------------------------------
# Nix Installation
# ------------------------------------------------------------------------------
get_nix_status() {
    if [ "$OS_TYPE" = "nixos" ]; then
        NIX_STATUS="builtin"
    elif [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
        NIX_STATUS="multi-installed"
    elif [ -f "$USER_HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        NIX_STATUS="single-installed"
    else
        NIX_STATUS="not-installed"
    fi
    say "Nix status: $NIX_STATUS"
}
source_nix_env() {
    if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
        # shellcheck source=/dev/null
        source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    elif [ -f "$USER_HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        # shellcheck source=/dev/null
        source "$USER_HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
}
nix_install() {
    if [ "$NIX_STATUS" != "not-installed" ]; then
        say "Nix is already installed ($NIX_STATUS). Skipping installation."
        return 0
    fi
    local install_type="multi"
    if [ "$OS_TYPE" = "linux" ] && [ "$IS_ROOT_USER" = false ] && [ "$IS_SUDO_USER" = false ]; then
        read -rp "Choose installation type (1. Single-user 2. Multi-user) [2]: " choice
        case "${choice:-2}" in
            1) install_type="single" ;;
            2) install_type="multi" ;;
            *) err "Invalid choice" ;;
        esac
    fi
    say "Installing Nix ($install_type)..."
    local install_args=("--no-channel-add")
    if [ "$install_type" = "multi" ]; then
        install_args+=("--daemon")
        NIX_INSTALLER_YES=1 run_as_root bash <(curl --proto '=https' --tlsv1.2 -L "$NIX_INSTALLER_URL") "${install_args[@]}"
    else
        # Single user MUST NOT be executed as root. Drop privileges.
        run_as_user bash <(curl --proto '=https' --tlsv1.2 -L "$NIX_INSTALLER_URL") "${install_args[@]}"
    fi
    get_nix_status
    source_nix_env
    check_cmd nix || err "Nix installation failed or not sourced properly."
    success "Nix installed successfully."
}
# ------------------------------------------------------------------------------
# Nix Configuration
# ------------------------------------------------------------------------------
nix_config() {
    say "Configuring Nix environment..."
    local nix_conf_content
    nix_conf_content="$(cat <<EOF
experimental-features = nix-command flakes
substituters = ${NIX_SUBSTITUTERS}
trusted-substituters = ${NIX_SUBSTITUTERS}
trusted-public-keys = ${NIX_TRUSTED_PUBLIC_KEYS}
builders-use-substitutes = true
auto-optimise-store = true
sandbox-fallback = false
EOF
)"
    case "$NIX_STATUS" in
        builtin|multi-installed)
            local nix_conf="/etc/nix/nix.conf"
            run_as_root mkdir -p /etc/nix
            run_as_root chmod 755 /etc/nix
            echo "$nix_conf_content" | run_as_root tee "$nix_conf" > /dev/null
            if ! id -nG "$USER_NAME" | grep -qw "nixbld" 2>/dev/null; then
                run_as_root usermod -aG nixbld "$USER_NAME"
            fi
            if command -v systemctl >/dev/null 2>&1; then
                run_as_root systemctl daemon-reload
                run_as_root systemctl restart nix-daemon.service
            fi
            # Clean root config conflict
            [ -f /root/.config/nix/nix.conf ] && run_as_root rm -rf /root/.config/nix/nix.conf
            ;;
        single-installed)
            local nix_conf_dir="$USER_HOME/.config/nix"
            # run_as_user prevents root ownership bug
            run_as_user mkdir -p "$nix_conf_dir"
            run_as_user chmod 755 "$nix_conf_dir"
            echo "$nix_conf_content" | run_as_user tee "$nix_conf_dir/nix.conf" > /dev/null
            ;;
    esac
    source_nix_env
    fix_cache_permissions
    success "Nix configuration applied."
}
nix_channel() {
    say "Adding Nixpkgs registry..."
    # Always add registry for the target normal user to prevent Nix EUID=0 HOME fallback warnings.
    # We don't need to add it for the root user specifically.
    run_as_user nix registry add nixpkgs "$NIXPKGS_URL"
}
fix_cache_permissions() {
    if [ "$NIX_STATUS" = "multi-installed" ] || [ "$NIX_STATUS" = "builtin" ]; then
        say "Fixing Nix cache permissions..."
        local user_group="$(id -gn "$USER_NAME" 2>/dev/null || echo "$USER_NAME")"
        [ -d "/root/.cache/nix" ] && run_as_root chown -Rf root:root /root/.cache/nix 2>/dev/null || true
        [ -d "$USER_HOME/.cache/nix" ] && run_as_root chown -Rf "$USER_NAME:$user_group" "$USER_HOME/.cache/nix" 2>/dev/null || true
        [ -d "$USER_HOME/.config/nix" ] && run_as_root chown -Rf "$USER_NAME:$user_group" "$USER_HOME/.config/nix" 2>/dev/null || true
        [ -d "$USER_HOME/.config/home-manager" ] && run_as_root chown -Rf "$USER_NAME:$user_group" "$USER_HOME/.config/home-manager" 2>/dev/null || true
    fi
}
# ------------------------------------------------------------------------------
# Disko & Flake Application
# ------------------------------------------------------------------------------
disk_partition() {
    if [ "$OS_TYPE" = "nixos" ] && [ "$IS_LIVE_CD" = true ]; then
        local mounts=$(grep -E '^/dev/(sd|nvme|vd|mmcblk|hd|xvd)' /proc/mounts | grep -v 'loop')
        if [ -n "$mounts" ]; then
            say "Partitions already mounted. Skipping disk partitioning."
        else
            say "No partitions mounted. Starting Disko partitioning..."
            if [ ! -f "$DISKO_FILE_PATH" ]; then
                err "Disko config not found at $DISKO_FILE_PATH"
            fi
            run_as_root nix run nixpkgs#disko -- --mode disko "$DISKO_FILE_PATH"
        fi
    fi
}
flake_load() {
    say "Loading Flake configuration..."
    case "$OS_TYPE" in
        nixos)
            run_as_root mkdir -p /etc/nixos/
            warn "Copying current directory flake files to /etc/nixos/"
            run_as_root cp -r ./* /etc/nixos/
            ;;
        linux)
            local target_dir="$USER_HOME/.config/home-manager"
            run_as_user mkdir -p "$target_dir"
            warn "Copying current directory flake files to $target_dir"
            run_as_user cp -r ./* "$target_dir"
            ;;
        darwin)
            local target_dir="$USER_HOME/.config/nix-darwin"
            run_as_user mkdir -p "$target_dir"
            warn "Copying current directory flake files to $target_dir"
            run_as_user cp -r ./* "$target_dir"
            ;;
    esac
}
flake_apply() {
    say "Applying Flake configuration..."
    source_nix_env
    read -rp "Apply flake configuration now? (Y/n) " confirm
    if [[ ! ${confirm:-Y} =~ ^[Yy]$ ]]; then
        say "Skipping flake application."; return 0
    fi
    case "$OS_TYPE" in
        nixos)
            if [ "$IS_LIVE_CD" = true ]; then
                run_as_root nixos-generate-config --dir /etc/nixos/
                run_as_root nixos-install --flake /etc/nixos/#nixos --impure
            else
                run_as_root nixos-rebuild switch --flake /etc/nixos/ --impure
            fi
            ;;
        linux)
            run_as_user nix run nixpkgs#home-manager -- switch --flake "$USER_HOME/.config/home-manager" --impure -b backup
            ;;
        darwin)
            run_as_user nix run nix-darwin -- switch --flake "$USER_HOME/.config/nix-darwin" --impure
            ;;
    esac
    fix_cache_permissions
}
# ------------------------------------------------------------------------------
# Main Entry Point
# ------------------------------------------------------------------------------
main() {
    get_system_info
    pre_program_install
    get_nix_status
    nix_install
    nix_config
    nix_channel
    disk_partition
    flake_load
    flake_apply
    say "Running validation test..."
    source_nix_env
    run_as_user nix run nixpkgs#hello
    success "Deployment completed successfully!"
}
main "$@"