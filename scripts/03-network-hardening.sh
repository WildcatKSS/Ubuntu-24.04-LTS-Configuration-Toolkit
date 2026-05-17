#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      03-network-hardening
# SUMMARY:     Disable cloud-init, UFW (SSH-only), IPv6, fail2ban
# DEPENDS:     02-ip-config
# IDEMPOTENT:  yes
# DESTRUCTIVE: no
# ADDED:       1.0.0
# CHANGED:     1.0.2

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# 1. Disable cloud-init
if plan_action "disable cloud-init"; then
    if [ ! -f /etc/cloud/cloud-init.disabled ]; then
        mkdir -p /etc/cloud
        touch /etc/cloud/cloud-init.disabled
        log_info "Created /etc/cloud/cloud-init.disabled"
    fi
    for svc in cloud-init cloud-config cloud-final cloud-init-local; do
        if run_quiet systemctl list-unit-files "${svc}.service" \
            && ! run_quiet systemctl is-enabled "${svc}.service" | grep -q masked; then
            run_quiet systemctl mask "${svc}.service" || true
        fi
    done
fi

# 2. Remove NetworkManager
if plan_action "purge network-manager if installed"; then
    pkg_purge network-manager network-manager-gnome
fi

# 3. Enable systemd-networkd
if plan_action "ensure systemd-networkd is enabled and active"; then
    system_service_enable_start systemd-networkd || true
fi

# 4. UFW
if plan_action "configure UFW (default deny in / allow out, rules for active services)"; then
    pkg_install ufw

    # Check if IPv6 is disabled on system
    ipv6_disabled=0
    if [ -f /etc/sysctl.d/99-ipv6.conf ] && grep -q 'net.ipv6.conf.all.disable_ipv6 = 1' /etc/sysctl.d/99-ipv6.conf; then
        ipv6_disabled=1
    fi

    # Disable IPv6 in UFW config if IPv6 is disabled on system
    if [ "$ipv6_disabled" -eq 1 ] && [ -f /etc/default/ufw ]; then
        if grep -q '^IPV6=yes' /etc/default/ufw; then
            sed -i 's/^IPV6=yes/IPV6=no/' /etc/default/ufw
            log_info "Disabled IPv6 in UFW config (/etc/default/ufw)"
        fi
    fi

    if run_quiet ufw status | grep -q 'Status: active'; then
        log_info "UFW already active"
    else
        run_quiet ufw --force reset
        run_quiet ufw default deny incoming
        run_quiet ufw default allow outgoing
        run_quiet ufw --force enable
        log_info "UFW enabled with default policy"
    fi

    # Load inbound-allowed services from config (default: ssh)
    inbound_services="${INBOUND_ALLOWED_SERVICES:-ssh}"

    # Add UFW rules for services that are both installed AND in inbound-allowed list
    # SSH — check if installed and allowed inbound
    ssh_installed=0
    if [ -f /etc/systemd/system/ssh.service ] || [ -f /etc/systemd/system/sshd.service ] || \
       [ -f /usr/lib/systemd/system/ssh.service ] || [ -f /usr/lib/systemd/system/sshd.service ]; then
        ssh_installed=1
    fi
    if [ "$ssh_installed" -eq 1 ] && echo "$inbound_services" | grep -qo '\bssh\b'; then
        if ! run_quiet ufw status | grep -q '22/tcp'; then
            run_quiet ufw allow 22/tcp comment 'SSH'
            log_info "Added UFW rule for SSH (22/tcp) — configured in INBOUND_ALLOWED_SERVICES"
        fi
    fi

    # Postfix (SMTP) — check if installed and allowed inbound
    if [ -f /etc/systemd/system/postfix.service ] || [ -f /usr/lib/systemd/system/postfix.service ]; then
        if echo "$inbound_services" | grep -qo '\bpostfix\b'; then
            for port in 25 587; do
                if ! run_quiet ufw status | grep -q "$port/tcp"; then
                    run_quiet ufw allow "$port/tcp" comment 'SMTP' || true
                    log_info "Added UFW rule for SMTP ($port/tcp) — configured in INBOUND_ALLOWED_SERVICES"
                fi
            done
        fi
    fi

    # Chronyd (NTP) — check if installed and allowed inbound (rarely needed)
    if echo "$inbound_services" | grep -qo '\bchronyd\b'; then
        if [ -f /etc/systemd/system/chrony.service ] || [ -f /etc/systemd/system/chronyd.service ] || \
           [ -f /usr/lib/systemd/system/chrony.service ] || [ -f /usr/lib/systemd/system/chronyd.service ]; then
            if ! run_quiet ufw status | grep -q '123/udp'; then
                run_quiet ufw allow 123/udp comment 'NTP' || true
                log_info "Added UFW rule for NTP (123/udp) — configured in INBOUND_ALLOWED_SERVICES"
            fi
        fi
    fi
fi

# 5. Disable IPv6 (sysctl + grub)
if plan_action "persistently disable IPv6"; then
    cat >/etc/sysctl.d/99-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    run_quiet sysctl -p /etc/sysctl.d/99-ipv6.conf
    log_info "IPv6 disabled via sysctl"

    if [ -f /etc/default/grub ]; then
        if grep -q 'ipv6.disable=1' /etc/default/grub; then
            log_info "grub already has ipv6.disable=1"
        else
            sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 ipv6.disable=1"/' /etc/default/grub
            sed -i 's/  *ipv6.disable=1"/ ipv6.disable=1"/' /etc/default/grub
            if command -v update-grub >/dev/null 2>&1; then
                run_quiet update-grub || log_warn "update-grub failed (non-fatal)"
            fi
            log_info "Added ipv6.disable=1 to grub (effective after reboot)"
        fi
    fi
fi

# 6. Fail2ban with dynamic jails for active services
if plan_action "install fail2ban with jails for active services"; then
    pkg_install fail2ban

    # Generate jail.local dynamically based on installed services
    jail_config="/etc/fail2ban/jail.local"

    # Start with base configuration
    jail_content='# Fail2ban jail configuration — generated by script 03-network-hardening
# /etc/fail2ban/jail.local

[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd
ignoreip = 127.0.0.1/8

'

    # Load inbound-allowed services from config
    inbound_services="${INBOUND_ALLOWED_SERVICES:-ssh}"
    recidive_ports=""

    # Check for SSH service and enable sshd jail only if installed
    if [ -f /etc/systemd/system/ssh.service ] || [ -f /etc/systemd/system/sshd.service ] || \
       [ -f /usr/lib/systemd/system/ssh.service ] || [ -f /usr/lib/systemd/system/sshd.service ]; then
        jail_content+='[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = systemd

'
        log_info "Fail2ban: Enabled sshd jail"
        # Only add to recidive if this service is inbound-allowed
        if echo "$inbound_services" | grep -qo '\bssh\b'; then
            recidive_ports="ssh"
        fi
    fi

    # Check for postfix and add jails if installed
    if [ -f /etc/systemd/system/postfix.service ] || [ -f /usr/lib/systemd/system/postfix.service ]; then
        jail_content+='[postfix-sasl]
enabled = true
port    = smtp,submission,imap2,imaps,pop3,pop3s
logpath = /var/log/mail.log
backend = systemd

'
        log_info "Fail2ban: Enabled postfix-sasl jail"
        # Only add to recidive if this service is inbound-allowed
        if echo "$inbound_services" | grep -qo '\bpostfix\b'; then
            if [ -z "$recidive_ports" ]; then
                recidive_ports="smtp,submission,imap,pop3"
            else
                recidive_ports="$recidive_ports,smtp,submission,imap,pop3"
            fi
        fi
    fi

    # Recidive jail — punish repeat offenders on inbound-allowed services only
    if [ -n "$recidive_ports" ]; then
        jail_content+="[recidive]
enabled = true
logpath = /var/log/fail2ban.log
action  = iptables-multiport[name=recidive, port=\"http,https,$recidive_ports\", protocol=tcp]
          sendmail-whois[name=recidive, dest=root@localhost]
bantime = 86400
findtime = 86400
maxretry = 5

"
        log_info "Fail2ban: Enabled recidive jail for ports: $recidive_ports (inbound-allowed services only)"
    fi

    # Write the generated config
    if printf '%s' "$jail_content" > "$jail_config"; then
        log_info "Generated $jail_config with dynamic service jails"
        systemctl restart fail2ban || log_warn "fail2ban restart failed (non-fatal)"
    else
        log_error "Failed to write $jail_config"
    fi

    system_service_enable_start fail2ban || true
fi

log_info "Network hardening complete"
