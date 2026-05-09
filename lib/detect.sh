#!/bin/bash
# ==============================================================================
# detect.sh — System, user, nix-status, and hardware detection
# Populates all S_* state variables defined in common.sh
# ==============================================================================

# ------------------------------------------------------------------------------
# Main entry point
# ------------------------------------------------------------------------------
# Phase 0: Initial detection — NO third-party dependencies (no lspci, no lscpu required)
detect_all() {
    say "Detecting system information..."
    _detect_os_arch
    _detect_user_context
    _detect_nix_status
    _detect_hostname
    _detect_cpu_vendor     # Uses lscpu if available, falls back to /proc/cpuinfo
    _print_state_summary
}

# Phase 1: Hardware detection — requires lspci (installed in phase 1 prerequisites)
detect_hardware() {
    say "Detecting hardware..."
    _detect_gpu
    _detect_virtualization
    _print_hardware_summary
}

# ------------------------------------------------------------------------------
# OS + Architecture + LiveCD detection
# ------------------------------------------------------------------------------
_detect_os_arch() {
    local _ostype _cputype
    _ostype="$(uname -s)"
    _cputype="$(uname -m)"

    # --- Linux: detect NixOS vs generic vs Android ---
    if [ "$_ostype" = Linux ]; then
        if [ "$(uname -o)" = Android ]; then
            _ostype=Android
        elif [ -f /etc/os-release ]; then
            source /etc/os-release && [ "${ID:-}" = "nixos" ] && _ostype="NixOS"
        fi
    fi

    # --- Darwin: Rosetta handling ---
    if [ "$_ostype" = Darwin ]; then
        if [ "$_cputype" = i386 ]; then
            (sysctl hw.optional.x86_64 2>/dev/null || true) | grep -q ': 1' && _cputype=x86_64
        elif [ "$_cputype" = x86_64 ]; then
            (sysctl hw.optional.arm64 2>/dev/null || true) | grep -q ': 1' && _cputype=arm64
        fi
    fi

    # --- SunOS (unsupported but detected) ---
    if [ "$_ostype" = SunOS ]; then
        [ "$(/usr/bin/uname -o)" = illumos ] && _ostype=illumos
        [ "$_cputype" = i86pc ] && _cputype="$(isainfo -n)"
    fi

    # --- Normalize CPU arch ---
    case "$_cputype" in
        aarch64 | arm64)   S_CPU_ARCH=aarch64 ;;
        x86_64 | x86-64 | x64 | amd64) S_CPU_ARCH=x86_64 ;;
        *) err "Unsupported CPU architecture: $_cputype" ;;
    esac

    # --- Normalize OS type ---
    case "$_ostype" in
        NixOS)  S_OS_TYPE=nixos  ;;
        Linux)  S_OS_TYPE=linux  ;;
        Darwin) S_OS_TYPE=darwin ;;
        *)      err "Unsupported OS: $_ostype" ;;
    esac

    # --- Build ARCH string ---
    if [ "$S_OS_TYPE" = "nixos" ]; then
        S_ARCH="${S_CPU_ARCH}-linux"
    else
        S_ARCH="${S_CPU_ARCH}-${S_OS_TYPE}"
    fi

    # --- LiveCD detection (3-layer fallback from oh-my-nix) ---
    S_IS_LIVE_CD=false
    if [ -f /proc/cmdline ] && grep -qE 'boot=live|live\.iso|nixos-live' /proc/cmdline 2>/dev/null; then
        S_IS_LIVE_CD=true
    elif mount | grep -qE ' / .*ro,' 2>/dev/null && [ -f /proc/mounts ] && grep -qE 'iso9660|squashfs' /proc/mounts 2>/dev/null; then
        S_IS_LIVE_CD=true
    elif [ -f /proc/mounts ] && grep -qE '/nix/store.*tmpfs|/nix/store.*overlay' /proc/mounts 2>/dev/null; then
        S_IS_LIVE_CD=true
    fi
}

# ------------------------------------------------------------------------------
# User context detection (root / sudo / normal)
# ------------------------------------------------------------------------------
_detect_user_context() {
    S_USER_NAME=$(whoami)
    S_IS_ROOT=false
    S_IS_SUDO=false

    if [ "$EUID" -eq 0 ]; then
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            # Running via sudo — target the original user
            S_IS_SUDO=true
            S_USER_NAME="$SUDO_USER"
        else
            # Raw root — find the first real normal user
            S_IS_ROOT=true
            S_USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || awk -F: '$3>=1000 && $1!="nobody"{print $1;exit}' /etc/passwd)}"
        fi
    fi

    # Special case: NixOS LiveCD or NixOS with 'nixos' user — prompt for username
    if [ "$S_OS_TYPE" = "nixos" ] && { [ "$S_IS_LIVE_CD" = true ] || [ "$S_USER_NAME" = "nixos" ]; }; then
        local input_user
        while true; do
            read -rp "Enter username: " input_user
            if [[ -n "$input_user" && "$input_user" != "root" ]]; then
                S_USER_NAME="$input_user"
                break
            else
                warn "Please enter a valid non-root username."
            fi
        done
    fi

    # If root and there are multiple normal users, let them choose
    if [ "$S_USER_NAME" = "root" ] && [ -f /etc/passwd ]; then
        local user_list=()
        while IFS=: read -r username _ uid _ _ home shell; do
            if [[ $uid -ge 1000 && $shell != *"nologin" && $shell != *"/false" ]]; then
                user_list+=("$username")
            fi
        done < /etc/passwd

        if [ ${#user_list[@]} -ge 2 ]; then
            echo ""
            echo "Available users:"
            for i in "${!user_list[@]}"; do
                echo "$((i+1))) ${user_list[$i]}"
            done
            local choice
            while true; do
                read -rp "Select user (1-${#user_list[@]}): " choice
                if [[ $choice =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#user_list[@]} ]]; then
                    S_USER_NAME="${user_list[$((choice-1))]}"
                    break
                else
                    warn "Invalid input, please enter 1-${#user_list[@]}"
                fi
            done
        elif [ ${#user_list[@]} -eq 1 ]; then
            S_USER_NAME="${user_list[0]}"
        fi
    fi

    S_USER_HOME=$(eval echo "~$S_USER_NAME")
}

# ------------------------------------------------------------------------------
# Nix installation status detection
# ------------------------------------------------------------------------------
_detect_nix_status() {
    if [ "$S_OS_TYPE" = "nixos" ]; then
        S_NIX_STATUS="builtin"
    elif [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
        S_NIX_STATUS="multi-installed"
    elif [ -f "$S_USER_HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        S_NIX_STATUS="single-installed"
        # Single-user install requires normal user context
        if [ "$S_IS_ROOT" = true ] || [ "$S_IS_SUDO" = true ]; then
            warn "Single-user Nix detected but running with elevated privileges."
            warn "Re-executing as normal user '$S_USER_NAME'..."
            downgrade_privilege "$@"
        fi
        source "$S_USER_HOME/.nix-profile/etc/profile.d/nix.sh"
    else
        S_NIX_STATUS="not-installed"
    fi
}

# ------------------------------------------------------------------------------
# Hostname detection
# ------------------------------------------------------------------------------
_detect_hostname() {
    S_HOST_NAME=$(hostname)
    if [ "$S_OS_TYPE" = "nixos" ] && [ "$S_IS_LIVE_CD" = true ]; then
        local host_name
        read -rp "Enter hostname (default: $S_HOST_NAME): " host_name
        S_HOST_NAME=${host_name:-$S_HOST_NAME}
    fi
}

# ------------------------------------------------------------------------------
# Hardware detection (GPU, IOMMU, KVM) — requires lspci from phase 1
# ------------------------------------------------------------------------------
_detect_cpu_vendor() {
    local _cpuvendor
    if check_cmd lscpu; then
        _cpuvendor=$(lscpu | grep -E 'Vendor ID|厂商 ID' | awk '{print $3}')
    elif [ -f /proc/cpuinfo ]; then
        _cpuvendor=$(grep 'vendor_id' /proc/cpuinfo | head -n1 | awk '{print $3}')
    fi

    case "${_cpuvendor:-unknown}" in
        GenuineIntel | Intel)       S_CPU_VENDOR=intel ;;
        AuthenticAMD | AMD)         S_CPU_VENDOR=amd   ;;
        *)                          S_CPU_VENDOR=unknown ;;
    esac
}

# Normalize PCI BusID (handles WSL and other non-standard lspci output)
_strip_leading_zeros() {
    local val="${1:-0}"
    val="$(printf '%s' "$val" | sed -E 's/^0+//')"
    printf '%s' "${val:-0}"
}

_normalize_pci_bus_id() {
    local addr="$1"
    local parts
    read -ra parts <<< "${addr//[:.]/ }"
    local len=${#parts[@]}
    if (( len < 3 )); then
        printf '%s' "$addr"
        return
    fi
    local bus="${parts[$((len-3))]}"
    local dev="${parts[$((len-2))]}"
    local func="${parts[$((len-1))]}"
    printf 'PCI:%s:%s:%s' \
        "$(_strip_leading_zeros "$bus")" \
        "$(_strip_leading_zeros "$dev")" \
        "$(_strip_leading_zeros "$func")"
}

_detect_gpu() {
    if ! check_cmd lspci; then
        warn "lspci not available — GPU detection skipped"
        return 0
    fi

    local gpus
    gpus="$(lspci -D -d ::03xx 2>/dev/null)" || true

    if [ -z "$gpus" ]; then
        warn "No VGA-compatible GPU detected"
        return 0
    fi

    say "Detected GPUs:"
    local idx=1
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local addr="${line%% *}"
        local desc="${line#* }"
        printf "  %d. %-4s | %s\n" \
            "$idx" \
            "$(_normalize_pci_bus_id "$addr")" \
            "$desc"
        ((idx++))
    done <<< "$gpus"
}

_detect_virtualization() {
    local cpu_flag cpu_name kvm_mod

    case "$S_CPU_VENDOR" in
        intel) cpu_flag="vmx"; cpu_name="Intel VT-x"; kvm_mod="kvm_intel" ;;
        amd)   cpu_flag="svm"; cpu_name="AMD-V";     kvm_mod="kvm_amd"   ;;
        *)     return 0 ;;  # Unknown vendor — skip virt detection
    esac

    # CPU virtualization support
    if grep -qw "$cpu_flag" /proc/cpuinfo 2>/dev/null && [ -d "/sys/module/$kvm_mod" ]; then
        S_HAS_KVM=true
    fi

    # IOMMU support
    if shopt -s nullglob 2>/dev/null; then
        local dirs=(/sys/kernel/iommu_groups/*)
        if [ "${#dirs[@]}" -gt 0 ]; then
            S_HAS_IOMMU=true
        fi
    fi
    return 0  # Ensure function always returns success (set -e safe)
}

# ------------------------------------------------------------------------------
# Print summary of all detected state
# ------------------------------------------------------------------------------
_print_state_summary() {
    echo ""
    say "=== System Information ==="
    say "CPU:           $S_CPU_VENDOR ($S_CPU_ARCH)"
    say "Architecture:  $S_ARCH"
    say "OS Type:       $S_OS_TYPE (Live CD: $S_IS_LIVE_CD)"
    say "Hostname:      $S_HOST_NAME"
    say "User:          $S_USER_NAME (home: $S_USER_HOME)"
    say "Root:          $S_IS_ROOT"
    say "Sudo:          $S_IS_SUDO"
    say "Nix Status:    $S_NIX_STATUS"
    say "========================="
    echo ""
}

_print_hardware_summary() {
    echo ""
    say "=== Hardware Information ==="
    say "KVM:           $S_HAS_KVM"
    say "IOMMU:         $S_HAS_IOMMU"
    say "============================"
    echo ""
}
