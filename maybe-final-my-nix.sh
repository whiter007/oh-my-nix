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
