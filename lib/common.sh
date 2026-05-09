#!/bin/bash
# ==============================================================================
# common.sh — Constants, logging, router, privilege helpers
# This file must be sourced first (all other modules depend on it).
# ==============================================================================

# ------------------------------------------------------------------------------
# Global Configuration & Constants
# ------------------------------------------------------------------------------
readonly NIX_SUBSTITUTERS="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://mirror.sjtu.edu.cn/nix-channels/store https://mirrors.cqupt.edu.cn/nix-channels/store https://cache.nixos.org"
readonly NIX_TRUSTED_KEYS="cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= mirrors.tuna.tsinghua.edu.cn/nix-channels/store:rSzv032o86Rxxhl6/7aYRl0v56Kza+4+4G8q0aT+28A= mirrors.ustc.edu.cn/nix-channels/store:o9ien6A6Y75/32Jdl3lZF52E6hDUmD+86L948YH9QyU="
readonly NIXPKGS_TARBALL="https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable/nixexprs.tar.xz"
readonly NIX_INSTALLER_URL="https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install"
readonly DEFAULT_DISKO_PATH="${SCRIPT_DIR}/config/disko-config.nix"

# Force substituters and flakes for current script execution process
export NIX_CONFIG="experimental-features = nix-command flakes
substituters = ${NIX_SUBSTITUTERS}
trusted-substituters = ${NIX_SUBSTITUTERS}
trusted-public-keys = ${NIX_TRUSTED_KEYS}"

# ------------------------------------------------------------------------------
# Global State Variables (populated by detect.sh)
# ------------------------------------------------------------------------------
S_OS_TYPE=""            # nixos | linux | darwin
S_ARCH=""               # x86_64-linux | aarch64-linux | x86_64-darwin | aarch64-darwin
S_IS_LIVE_CD="false"    # true | false
S_USER_NAME=""          # target normal user (never root)
S_USER_HOME=""          # /home/$S_USER_NAME or /Users/$S_USER_NAME
S_IS_ROOT="false"       # true if EUID=0 and no SUDO_USER
S_IS_SUDO="false"       # true if EUID=0 and SUDO_USER is set
S_NIX_STATUS=""         # builtin | multi-installed | single-installed | not-installed
S_HOST_NAME=""           # hostname (used for nixosConfigurations key)
S_CPU_VENDOR=""         # intel | amd | unknown
S_CPU_ARCH=""            # aarch64 | x86_64
S_HAS_IOMMU="false"     # true | false
S_HAS_KVM="false"       # true | false
S_SWAP_SIZE=""           # Swap partition size (e.g. "8G")

# ------------------------------------------------------------------------------
# Logging Functions (glm-my-nix style)
# ------------------------------------------------------------------------------
__print() {
    local level="$1"; shift
    local color=""
    case "$level" in
        info)    color='\033[1;34m' ;;
        warn)    color='\033[1;33m' ;;
        error)   color='\033[1;31m' ;;
        success) color='\033[1;32m' ;;
    esac
    if [ -t 1 ]; then
        printf "${color}[%s]\033[0m %s\n" "$level" "$*" >&2
    else
        printf "[%s] %s\n" "$level" "$*" >&2
    fi
}
say()     { __print info    "$@"; }
warn()    { __print warn    "$@"; }
err()     { __print error   "$@"; exit 1; }
success() { __print success "$@"; }

check_cmd() { command -v "$1" > /dev/null 2>&1; }
need_cmd()  { check_cmd "$1" || err "Required command '$1' not found."; }

# ------------------------------------------------------------------------------
# Privilege Helpers (the only two — no raw sudo calls anywhere else)
# ------------------------------------------------------------------------------

# Execute command as root. If already root, run directly; otherwise use sudo.
# Always passes critical env vars to prevent HOME/ownership issues.
run_as_root() {
    if [ "$EUID" -ne 0 ]; then
        sudo env PATH="$PATH" USER="$S_USER_NAME" HOME="$S_USER_HOME" NIX_CONFIG="${NIX_CONFIG:-}" "$@"
    else
        env PATH="$PATH" USER="$S_USER_NAME" HOME="$S_USER_HOME" NIX_CONFIG="${NIX_CONFIG:-}" "$@"
    fi
}

# Execute command as the target normal user. Uses `sudo -u` to fully switch
# context, which prevents Nix from complaining about $HOME ownership when
# called from a root/sudo execution context.
run_as_user() {
    if [ "$EUID" -eq 0 ]; then
        sudo -u "$S_USER_NAME" env PATH="$PATH" USER="$S_USER_NAME" HOME="$S_USER_HOME" NIX_CONFIG="${NIX_CONFIG:-}" "$@"
    else
        env PATH="$PATH" USER="$S_USER_NAME" HOME="$S_USER_HOME" NIX_CONFIG="${NIX_CONFIG:-}" "$@"
    fi
}

# ------------------------------------------------------------------------------
# OS Router — the core dispatcher (like a backend controller router)
# ------------------------------------------------------------------------------

# Calls os_${S_OS_TYPE}_${phase} function.
# If no handler exists for this OS+phase combination, logs and skips silently.
# Usage: os_handler "install_prereqs"
#        os_handler "apply_flake"
os_handler() {
    local phase="$1"; shift
    local func="os_${S_OS_TYPE}_${phase}"
    if declare -f "$func" >/dev/null 2>&1; then
        "$func" "$@"
    else
        say "Phase '$phase': no handler for os=$S_OS_TYPE (skipped)"
    fi
}

# ------------------------------------------------------------------------------
# Privilege Downgrade
# ------------------------------------------------------------------------------

# Re-execute this script as the target normal user.
# Used when single-user Nix install is needed but we're running as root/sudo.
downgrade_privilege() {
    if [ "$EUID" -eq 0 ]; then
        warn "Re-executing as normal user '$S_USER_NAME' for single-user operation..."
        exec sudo -u "$S_USER_NAME" -E HOME="$S_USER_HOME" bash "$0" "$@"
    fi
}

# ------------------------------------------------------------------------------
# Optional: Progress wrapper (from yeah-my-nix)
# ------------------------------------------------------------------------------
run_with_progress() {
    local msg="$1"; shift
    say "Start: $msg"
    if "$@"; then
        success "Done: $msg"
    else
        err "Failed: $msg — check logs and retry"
    fi
}
