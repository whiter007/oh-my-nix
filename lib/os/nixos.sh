#!/bin/bash
# ==============================================================================
# os/nixos.sh — NixOS phase handlers
# Called by os_handler() in common.sh
# ==============================================================================

# ------------------------------------------------------------------------------
# Phase 1: Install prerequisite tools
# ------------------------------------------------------------------------------
os_nixos_install_prereqs() {
    say "Checking NixOS prerequisites..."

    if ! check_cmd git; then
        warn "git not found — installing via nix profile..."
        run_as_root nix --option substituters "$NIX_SUBSTITUTERS" profile add nixpkgs#git
    else
        say "git found."
    fi

    if ! check_cmd lspci; then
        warn "lspci not found — installing pciutils via nix profile..."
        run_as_root nix --option substituters "$NIX_SUBSTITUTERS" profile add nixpkgs#pciutils
    else
        say "lspci found."
    fi
}

# ------------------------------------------------------------------------------
# Phase 3: Select disk + swap size (LiveCD only)
# ------------------------------------------------------------------------------
os_nixos_setup_disks() {
    if [ "$S_IS_LIVE_CD" != true ]; then
        say "Not a Live CD environment. Skipping disk setup."
        return 0
    fi

    # Check if partitions are already mounted
    local mounts
    mounts=$(grep -E '^/dev/(sd|nvme|vd|mmcblk|hd|xvd)' /proc/mounts 2>/dev/null | grep -v 'loop' || true)
    if [ -n "$mounts" ]; then
        say "Partitions already mounted. Skipping disk setup."
        return 0
    fi

    # Interactive disk + swap size selection
    _nixos_select_disk
    _nixos_select_swap_size
}

# ------------------------------------------------------------------------------
# Phase 3: Run Disko partitioning (LiveCD only)
# ------------------------------------------------------------------------------
os_nixos_generate_disko() {
    if [ "$S_IS_LIVE_CD" != true ]; then
        say "Not a Live CD environment. Skipping disko."
        return 0
    fi

    say "Running Disko partitioning on $S_SELECTED_DISK (swap: ${S_SWAP_SIZE:-none})..."
    run_as_root nix --option substituters "$NIX_SUBSTITUTERS" run nixpkgs#disko -- --mode disko "$DEFAULT_DISKO_PATH"
}

# ------------------------------------------------------------------------------
# Phase 3: Generate flake configuration
# ------------------------------------------------------------------------------
os_nixos_generate_flake() {
    warn "Copying flake files to /etc/nixos/"
    run_as_root mkdir -p /etc/nixos/
    shopt -s dotglob
    run_as_root cp -r ./* /etc/nixos/ 2>/dev/null || true
    shopt -u dotglob

    if [ "$S_IS_LIVE_CD" = true ]; then
        say "Live CD: generating hardware configuration..."
        run_as_root nixos-generate-config --dir /etc/nixos/
    fi
    success "Flake configuration loaded."
}

# ------------------------------------------------------------------------------
# Phase 3: Apply flake configuration
# ------------------------------------------------------------------------------
os_nixos_apply_flake() {
    if [ "$S_IS_LIVE_CD" = true ]; then
        warn "NixOS Live CD: installing system via flake..."
        run_as_root nixos-install --option extra-substituters "$NIX_SUBSTITUTERS" \
            --flake "/etc/nixos/#$S_HOST_NAME" --impure
    else
        warn "NixOS: applying flake configuration (nixos-rebuild switch)..."
        run_as_root nixos-rebuild switch --option extra-substituters "$NIX_SUBSTITUTERS" \
            --flake /etc/nixos/ --impure
    fi
    nix_fix_cache_permissions
}

# ------------------------------------------------------------------------------
# Celebrate
# ------------------------------------------------------------------------------
os_nixos_celebrate() {
    run_as_root nix --option extra-substituters "$NIX_SUBSTITUTERS" run nixpkgs#hello
    success "NixOS deployment completed successfully!"
}

# ==============================================================================
# Internal helpers
# ==============================================================================

_nixos_select_disk() {
    local disks
    mapfile -t disks < <(lsblk -d -o NAME,TYPE,SIZE,MODEL -n 2>/dev/null | awk '$2=="disk" {print $1,$3,$4}')

    if [ ${#disks[@]} -eq 0 ]; then
        err "No disks detected."
    fi

    echo ""
    say "=== Available Disks ==="
    lsblk
    for i in "${!disks[@]}"; do
        read -r name size model <<< "${disks[$i]}"
        echo "$((i+1))) /dev/$name — $size — ${model:-unknown model}"
    done

    local choice
    while true; do
        read -rp "Select target disk (1-${#disks[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#disks[@]} ]; then
            local selected_name
            selected_name=$(echo "${disks[$((choice-1))]}" | awk '{print $1}')
            S_SELECTED_DISK="/dev/$selected_name"
            say "Selected disk: $S_SELECTED_DISK"
            break
        else
            warn "Invalid input, please enter 1-${#disks[@]}."
        fi
    done
}

_nixos_select_swap_size() {
    echo ""
    say "=== Swap Partition ==="
    echo "Recommended swap sizes:"
    echo "  0  — No swap"
    echo "  2G — Minimal (RAM < 8G)"
    echo "  4G — Small (RAM 8-16G)"
    echo "  8G — Standard (RAM 16-32G, for hibernation)"
    echo "  16G — Large (RAM > 32G)"
    echo ""

    local swap_size
    while true; do
        read -rp "Enter swap size (e.g., 0, 2G, 4G, 8G, 16G) [default: 8G]: " swap_size
        swap_size=${swap_size:-8G}
        if [[ "$swap_size" =~ ^[0-9]+[GTM]?$ ]] || [ "$swap_size" = "0" ]; then
            S_SWAP_SIZE="$swap_size"
            say "Swap size: $S_SWAP_SIZE"
            break
        else
            warn "Invalid format. Use a number with optional G/T/M suffix (e.g. 8G, 0, 512M)."
        fi
    done
}
