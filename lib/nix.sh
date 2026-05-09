#!/bin/bash
# ==============================================================================
# nix.sh — Nix installation and configuration
# Dispatches by S_NIX_STATUS, NOT by S_OS_TYPE (cross-cutting concern).
# ==============================================================================

# ------------------------------------------------------------------------------
# Source Nix environment (profile)
# ------------------------------------------------------------------------------
source_nix_env() {
    if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
        # shellcheck source=/dev/null
        source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    elif [ -f "$S_USER_HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        # shellcheck source=/dev/null
        source "$S_USER_HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
}

# ------------------------------------------------------------------------------
# Phase 1: Ensure Nix is installed
# ------------------------------------------------------------------------------
nix_ensure_installed() {
    case "$S_NIX_STATUS" in
        builtin)
            say "Nix is built into NixOS — skipping installation."
            ;;
        multi-installed | single-installed)
            say "Nix is already installed ($S_NIX_STATUS) — skipping installation."
            source_nix_env
            ;;
        not-installed)
            local install_type
            install_type=$(_nix_prompt_install_type)
            _nix_run_installer "$install_type"
            _detect_nix_status
            source_nix_env
            check_cmd nix || err "Nix installation succeeded but 'nix' command not found in PATH."
            success "Nix installed successfully ($S_NIX_STATUS)."
            ;;
    esac
}

_nix_prompt_install_type() {
    local install_type="multi"
    if [ "$S_OS_TYPE" = "linux" ] && [ "$S_IS_ROOT" = false ] && [ "$S_IS_SUDO" = false ]; then
        # Normal user on Linux: offer choice
        local choice
        read -rp "Choose installation type (1. Single-user  2. Multi-user) [2]: " choice
        case "${choice:-2}" in
            1) install_type="single" ;;
            2) install_type="multi" ;;
            *) err "Invalid choice — please enter 1 or 2." ;;
        esac
    fi
    # root/sudo users: default to multi-user without asking
    # darwin: default to multi-user (when implemented)
    echo "$install_type"
}

_nix_run_installer() {
    local install_type="$1"
    local args=("--no-channel-add")

    say "Installing Nix ($install_type-user)..."
    if [ "$install_type" = "multi" ]; then
        args+=("--daemon")
        NIX_INSTALLER_YES=1 run_as_root bash <(curl --proto '=https' --tlsv1.2 -L "$NIX_INSTALLER_URL") "${args[@]}"
    else
        # Single-user MUST run as normal user. Downgrade if needed.
        if [ "$S_IS_ROOT" = true ] || [ "$S_IS_SUDO" = true ]; then
            warn "Single-user install requires normal user context. Downgrading privilege."
            downgrade_privilege "$@"
        fi
        run_as_user bash <(curl --proto '=https' --tlsv1.2 -L "$NIX_INSTALLER_URL") "${args[@]}"
    fi
}

# ------------------------------------------------------------------------------
# Phase 2: Configure Nix
# ------------------------------------------------------------------------------
nix_configure() {
    say "Configuring Nix ($S_NIX_STATUS)..."
    case "$S_NIX_STATUS" in
        builtin)
            _configure_nix_builtin
            ;;
        multi-installed)
            _configure_nix_multi
            ;;
        single-installed)
            _configure_nix_single
            ;;
        *)
            warn "Nix not installed — skipping configuration."
            return 0
            ;;
    esac
    _add_nix_registry
    source_nix_env
    success "Nix configuration applied."
}

# NixOS built-in: nix.conf is managed by the flake (nix-settings.nix).
# We only handle runtime concerns: nixbld group and conflict cleanup.
_configure_nix_builtin() {
    say "NixOS built-in Nix: configuration is managed by flake nix-settings.nix."

    # nixbld group
    if ! id -nG "$S_USER_NAME" 2>/dev/null | grep -qw "nixbld"; then
        run_as_root usermod -aG nixbld "$S_USER_NAME"
        say "Added $S_USER_NAME to nixbld group."
    fi

    # Clean root config conflict
    [ -f /root/.config/nix/nix.conf ] && run_as_root rm -rf /root/.config/nix/nix.conf
}

_configure_nix_multi() {
    local conf="/etc/nix/nix.conf"
    run_as_root mkdir -p /etc/nix
    run_as_root chmod 755 /etc/nix

    # Write nix.conf
    _generate_nix_conf_content "multi" | run_as_root tee "$conf" > /dev/null
    say "Written nix.conf to $conf"

    # nixbld group
    if ! id -nG "$S_USER_NAME" 2>/dev/null | grep -qw "nixbld"; then
        run_as_root usermod -aG nixbld "$S_USER_NAME"
        say "Added $S_USER_NAME to nixbld group."
        say "Verified groups: $(id -nG "$S_USER_NAME")"
    fi

    # Daemon reload + verify (from oh-my-nix)
    if command -v systemctl >/dev/null 2>&1; then
        say "Reloading systemd and restarting nix-daemon..."
        run_as_root systemctl daemon-reload
        run_as_root systemctl restart nix-daemon.service

        # Wait for daemon to become active
        local waited=0
        while ! run_as_root systemctl is-active --quiet nix-daemon.service; do
            sleep 1
            waited=$((waited + 1))
            if [ "$waited" -gt 30 ]; then
                warn "nix-daemon did not become active within 30s"
                break
            fi
        done

        # Verify daemon is responding
        source_nix_env
        if nix store ping 2>/dev/null; then
            success "nix-daemon is active and responding."
        else
            warn "nix-daemon is active but not responding to ping."
        fi
    fi

    # Clean conflicting user configs
    [ -f /root/.config/nix/nix.conf ] && run_as_root rm -rf /root/.config/nix/nix.conf
    [ -f "$S_USER_HOME/.config/nix/nix.conf" ] && run_as_user rm -f "$S_USER_HOME/.config/nix/nix.conf"
}

_configure_nix_single() {
    local conf_dir="$S_USER_HOME/.config/nix"
    run_as_user mkdir -p "$conf_dir"
    run_as_user chmod 755 "$conf_dir"

    _generate_nix_conf_content "single" | run_as_user tee "$conf_dir/nix.conf" > /dev/null
    say "Written nix.conf to $conf_dir/nix.conf"
}

_generate_nix_conf_content() {
    local mode="$1"
    cat <<EOF
experimental-features = nix-command flakes
substituters = ${NIX_SUBSTITUTERS}
trusted-substituters = ${NIX_SUBSTITUTERS}
trusted-public-keys = ${NIX_TRUSTED_KEYS}
builders-use-substitutes = true
auto-optimise-store = true
sandbox-fallback = false
EOF
    if [ "$mode" = "multi" ]; then
        echo "trusted-users = root $S_USER_NAME"
    fi
}

_add_nix_registry() {
    say "Adding Nixpkgs registry..."
    run_as_user nix registry add nixpkgs "$NIXPKGS_TARBALL"
    # On multi-user / builtin, root also needs the registry
    if [ "$S_NIX_STATUS" = "builtin" ] || [ "$S_NIX_STATUS" = "multi-installed" ]; then
        run_as_root nix registry add nixpkgs "$NIXPKGS_TARBALL"
    fi
}

# ------------------------------------------------------------------------------
# Cache permission fix (from oh-my-nix)
# ------------------------------------------------------------------------------
nix_fix_cache_permissions() {
    if [ "$S_NIX_STATUS" = "multi-installed" ] || [ "$S_NIX_STATUS" = "builtin" ]; then
        local user_group="$(id -gn "$S_USER_NAME" 2>/dev/null || echo "$S_USER_NAME")"
        [ -d "/root/.cache/nix" ]               && run_as_root chown -Rf root:root                 /root/.cache/nix            2>/dev/null || true
        [ -d "$S_USER_HOME/.cache/nix" ]           && run_as_root chown -Rf "$S_USER_NAME:$user_group" "$S_USER_HOME/.cache/nix"           2>/dev/null || true
        [ -d "$S_USER_HOME/.config/nix" ]          && run_as_root chown -Rf "$S_USER_NAME:$user_group" "$S_USER_HOME/.config/nix"          2>/dev/null || true
        [ -d "$S_USER_HOME/.config/home-manager" ] && run_as_root chown -Rf "$S_USER_NAME:$user_group" "$S_USER_HOME/.config/home-manager" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# Phase confirmation helper — returns 0 if confirmed, 1 if skipped
# Usage: confirm_phase "Install prerequisites and Nix"
# ------------------------------------------------------------------------------
confirm_phase() {
    local description="$1"
    local reply
    read -rp "$description? (Y/n, default Y) " reply
    if [[ $reply =~ ^[Nn]$ ]]; then
        say "Skipping: $description."
        return 1
    fi
    return 0
}
