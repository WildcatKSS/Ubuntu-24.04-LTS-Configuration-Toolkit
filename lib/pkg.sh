#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
#
# lib/pkg.sh — Package management helpers (apt wrappers)

export DEBIAN_FRONTEND=noninteractive

# pkg_is_installed <pkg>
pkg_is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# pkg_install <pkg> [pkg ...]
# Installs only packages that are not yet present.
pkg_install() {
    local to_install=()
    local pkg
    for pkg in "$@"; do
        if pkg_is_installed "$pkg"; then
            log_info "Already installed: $pkg"
        else
            to_install+=("$pkg")
        fi
    done
    if [ "${#to_install[@]}" -eq 0 ]; then
        return 0
    fi
    log_info "Installing: ${to_install[*]}"
    if ! run_quiet apt install -y --no-install-recommends "${to_install[@]}"; then
        log_error "apt install failed for: ${to_install[*]}"
        return 1
    fi
}

# pkg_purge <pkg> [pkg ...]
# Purges only packages that are currently installed.
pkg_purge() {
    local to_purge=()
    local pkg
    for pkg in "$@"; do
        if pkg_is_installed "$pkg"; then
            to_purge+=("$pkg")
        fi
    done
    if [ "${#to_purge[@]}" -eq 0 ]; then
        return 0
    fi
    log_info "Purging: ${to_purge[*]}"
    run_quiet apt purge -y "${to_purge[@]}" || log_warn "Purge had errors for: ${to_purge[*]}"
}

# pkg_update — refresh apt indexes (cached for 60 minutes per run).
pkg_update() {
    local stamp="/tmp/.toolkit-apt-updated"
    if [ -f "$stamp" ] && [ "$(($(date +%s) - $(stat -c %Y "$stamp")))" -lt 3600 ]; then
        log_info "apt update skipped (cached)"
        return 0
    fi
    log_info "Running apt update"
    if ! run_quiet apt update -y; then
        log_error "apt update failed"
        return 1
    fi
    touch "$stamp"
}
