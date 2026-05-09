#!/bin/bash
set -eo pipefail

# ==============================================================================
# my-nix.sh — Nix One-Click Deployment Script
# Supports: NixOS (including LiveCD), Generic Linux, macOS (Darwin)
#
# Architecture: Router pattern — OS dispatch via os_handler() → os/*.sh
# Cross-cutting Nix install/configure in nix.sh (dispatches by NIX_STATUS)
#
# 3-Phase flow with Y/Enter confirmation before each phase
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source all modules in dependency order
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/nix.sh"
source "$SCRIPT_DIR/lib/os/nixos.sh"
source "$SCRIPT_DIR/lib/os/linux.sh"
source "$SCRIPT_DIR/lib/os/darwin.sh"

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    # =========================================================================
    # Phase 0: Initial Detection (no third-party deps — no lspci needed yet)
    # =========================================================================
    detect_all

    # =========================================================================
    # Phase 1: Install prerequisites + Nix
    # =========================================================================
    if confirm_phase "Phase 1 — Install prerequisites and Nix"; then
        os_handler "install_prereqs"      # OS-specific: git, curl, xz, lspci
        detect_hardware                    # Now lspci is available — scan GPU, IOMMU, KVM
        nix_ensure_installed              # Cross-cutting: install Nix if needed
    fi

    # =========================================================================
    # Phase 2: Configure Nix
    # =========================================================================
    if confirm_phase "Phase 2 — Configure Nix"; then
        nix_configure                     # Cross-cutting: nix.conf, nixbld, daemon
        nix_fix_cache_permissions         # Cross-cutting: fix cache ownership
    fi

    # =========================================================================
    # Phase 3: Flake deployment (disks → disko → flake → apply)
    # =========================================================================
    if confirm_phase "Phase 3 — Configure and apply flake"; then
        os_handler "setup_disks"          # NixOS LiveCD: select disk + swap size
        os_handler "generate_disko"       # NixOS LiveCD: run Disko partitioning
        os_handler "generate_flake"       # OS-specific: generate/copy flake files
        os_handler "apply_flake"          # OS-specific: nixos-rebuild / home-manager / darwin-rebuild
        os_handler "celebrate"            # OS-specific: run hello test
    fi
}

main "$@"
