#!/bin/bash
# ==============================================================================
# os/linux.sh — Generic Linux phase handlers
# Called by os_handler() in common.sh
# ==============================================================================

# ------------------------------------------------------------------------------
# Phase 1: Install prerequisite tools via native package manager
# ------------------------------------------------------------------------------
os_linux_install_prereqs() {
    say "Checking Linux prerequisites..."

    # Map: command → package-name (apt-specific variant after |)
    local cmds_to_pkgs="curl:curl xz:xz|xz-utils git:git lspci:pciutils"
    local missing_pkgs=()
    local pm="" install_cmd=""

    # Detect missing tools
    for item in $cmds_to_pkgs; do
        local cmd="${item%%:*}" pkg="${item#*:}"
        check_cmd "$cmd" || missing_pkgs+=("${pkg%|*}")
    done

    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        say "All prerequisites are installed."
        return 0
    fi

    warn "Missing tools: ${missing_pkgs[*]}"

    # Detect package manager (priority order)
    if   check_cmd oma;    then pm="oma"    ; install_cmd="oma install -y"
    elif check_cmd apt;     then pm="apt"     ; install_cmd="apt install -y"
    elif check_cmd dnf;     then pm="dnf"     ; install_cmd="dnf install -y"
    elif check_cmd yum;     then pm="yum"     ; install_cmd="yum install -y"
    elif check_cmd pacman;  then pm="pacman"  ; install_cmd="pacman -S --noconfirm"
    elif check_cmd zypper;  then pm="zypper"  ; install_cmd="zypper install -y"
    elif check_cmd apk;     then pm="apk"     ; install_cmd="apk add"
    fi

    # apt uses xz-utils instead of xz
    if [ "$pm" = "apt" ] || [ "$pm" = "oma" ]; then
        missing_pkgs=("${missing_pkgs[@]/xz/xz-utils}")
    fi

    if [ "$pm" = "oma" ]; then
        say "Tip: Run 'oma mirror' first if downloads are slow."
    fi

    if [ -n "$install_cmd" ]; then
        run_as_root $install_cmd "${missing_pkgs[@]}"
    else
        err "No supported package manager found. Please install manually: ${missing_pkgs[*]}"
    fi
}

# ------------------------------------------------------------------------------
# Phase 3: Generate flake configuration
# ------------------------------------------------------------------------------
os_linux_generate_flake() {
    local target="$S_USER_HOME/.config/home-manager"
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
os_linux_apply_flake() {
    local flake_path="$S_USER_HOME/.config/home-manager"
    warn "Applying home-manager flake configuration..."
    run_as_user nix run nixpkgs#home-manager -- switch \
        --flake "$flake_path" --impure -b backup
    nix_fix_cache_permissions
}

# ------------------------------------------------------------------------------
# Celebrate
# ------------------------------------------------------------------------------
os_linux_celebrate() {
    run_as_user nix run nixpkgs#hello
    success "Home-manager deployment completed successfully!"
}
