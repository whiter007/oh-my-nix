#!/bin/bash
# ==============================================================================
# os/darwin.sh — macOS (Darwin) phase handlers
# Called by os_handler() in common.sh
# ==============================================================================

# ------------------------------------------------------------------------------
# Phase 1: Install prerequisite tools
# ------------------------------------------------------------------------------
os_darwin_install_prereqs() {
    say "Checking Darwin prerequisites..."
    need_cmd git
    need_cmd curl
    if ! check_cmd lspci; then
        warn "lspci not found — GPU detection will be skipped."
    fi
}

# ------------------------------------------------------------------------------
# Phase 3: Generate flake configuration
# ------------------------------------------------------------------------------
os_darwin_generate_flake() {
    local target="$S_USER_HOME/.config/nix-darwin"
    run_as_user mkdir -p "$target"
    warn "Copying flake files to $target"
    shopt -s dotglob
    run_as_user cp -r ./* "$target" 2>/dev/null || true
    shopt -u dotglob
    success "Flake configuration loaded."
}

# ------------------------------------------------------------------------------
# Phase 3: Apply flake configuration
# ------------------------------------------------------------------------------
os_darwin_apply_flake() {
    local flake_path="$S_USER_HOME/.config/nix-darwin"
    warn "Applying nix-darwin flake configuration..."
    run_as_user nix run nix-darwin -- switch --flake "$flake_path" --impure
    nix_fix_cache_permissions
}

# ------------------------------------------------------------------------------
# Celebrate
# ------------------------------------------------------------------------------
os_darwin_celebrate() {
    run_as_user nix run nixpkgs#hello
    success "nix-darwin deployment completed successfully!"
}
