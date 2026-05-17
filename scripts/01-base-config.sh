#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      01-base-config
# SUMMARY:     System update, admin sudo user, unattended-upgrades
# DEPENDS:     00-preflight
# IDEMPOTENT:  yes
# DESTRUCTIVE: no
# ADDED:       1.0.0
# CHANGED:     1.0.2

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# 1. apt update + upgrade
if plan_action "apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y"; then
    pkg_update
    log_info "Running apt-get upgrade"
    run_quiet apt-get upgrade -y
    log_info "Running apt-get dist-upgrade"
    run_quiet apt-get dist-upgrade -y
fi

# 2. Admin credentials (from questionnaire or environment)
ADMIN_MODE_CREATE_USER="${ADMIN_MODE_CREATE_USER:-yes}"

if [ "$ADMIN_MODE_CREATE_USER" != "skip" ]; then
    if [ "$PLAN_MODE" != "1" ] && ([ -z "${ADMIN_USER:-}" ] || [ -z "${ADMIN_PASSWORD:-}" ]); then
        log_error "ADMIN_USER and ADMIN_PASSWORD must be set (run questionnaire or set environment)"
        exit 1
    fi
    if [ -n "${ADMIN_USER:-}" ]; then
        log_info "Admin user: $ADMIN_USER"
    fi
fi

# 3. Handle admin user based on mode
if [ "$PLAN_MODE" = "1" ]; then
    if [ "$ADMIN_MODE_CREATE_USER" = "skip" ]; then
        log_info "PLAN: skipping sudo user configuration"
    elif [ "$ADMIN_MODE_CREATE_USER" = "yes" ]; then
        log_info "PLAN: would create user ${ADMIN_USER:-<not set>} and add to sudo group"
    else
        log_info "PLAN: would change password for user ${ADMIN_USER:-<not set>}"
    fi
elif [ "$ADMIN_MODE_CREATE_USER" = "skip" ]; then
    log_info "Skipping sudo user configuration (user selected skip)"
elif [ "$ADMIN_MODE_CREATE_USER" = "yes" ]; then
    # Create new sudo user
    if system_user_exists "${ADMIN_USER}"; then
        log_info "User already exists: ${ADMIN_USER}"
    else
        log_info "Creating user: ${ADMIN_USER}"
        run_quiet useradd -m -s /bin/bash -G sudo "${ADMIN_USER}"
    fi

    # Set password
    if [ -n "${ADMIN_PASSWORD:-}" ]; then
        echo "${ADMIN_USER}:${ADMIN_PASSWORD}" | run_quiet chpasswd
        log_info "Password set for ${ADMIN_USER}"
    fi

    # Ensure sudo group membership
    if id -nG "${ADMIN_USER}" | tr ' ' '\n' | grep -qx sudo; then
        log_info "User ${ADMIN_USER} is in sudo group"
    else
        run_quiet usermod -aG sudo "${ADMIN_USER}"
        log_info "Added ${ADMIN_USER} to sudo group"
    fi
else
    # Change password for existing user
    if ! system_user_exists "${ADMIN_USER}"; then
        log_error "User does not exist: ${ADMIN_USER}"
        exit 1
    fi

    if [ -n "${ADMIN_PASSWORD:-}" ]; then
        echo "${ADMIN_USER}:${ADMIN_PASSWORD}" | run_quiet chpasswd
        log_info "Password changed for ${ADMIN_USER}"
    fi
fi

# 5. Clear sensitive variables
unset ADMIN_PASSWORD

# 6. unattended-upgrades
if [ "${AUTO_SECURITY_UPDATES:-true}" = "true" ]; then
    if plan_action "install and enable unattended-upgrades"; then
        pkg_install unattended-upgrades apt-listchanges
        if [ -f /etc/apt/apt.conf.d/20auto-upgrades ] \
           && grep -q 'APT::Periodic::Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then
            log_info "unattended-upgrades already enabled"
        else
            cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
            log_info "Enabled unattended-upgrades (20auto-upgrades)"
        fi
        if [ -n "${EMAIL_TO:-}" ] && [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
            if ! grep -q "^Unattended-Upgrade::Mail \"${EMAIL_TO}\"" /etc/apt/apt.conf.d/50unattended-upgrades; then
                sed -i "s|^//Unattended-Upgrade::Mail .*|Unattended-Upgrade::Mail \"${EMAIL_TO}\";|" \
                    /etc/apt/apt.conf.d/50unattended-upgrades
                log_info "Configured unattended-upgrades to mail $EMAIL_TO on errors"
            fi
        fi
    fi
fi

log_info "Base configuration complete"
