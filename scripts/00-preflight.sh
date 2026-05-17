#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      00-preflight
# DESC:     Verify Ubuntu Server 26.04 LTS, network, disk space, and apt locks
# DEPENDS:
# IDEMPOTENT:  yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"
errors=0
plan_warnings=0

# Runtime preconditions (network, apt lock, free disk) only matter for an
# actual run. In plan mode they are reported as warnings so the read-only
# audit can complete without touching the system.
preflight_runtime_fail() {
    local message="$1"
    if [ "$PLAN_MODE" = "1" ]; then
        log_warn "PLAN: would fail: $message"
        plan_warnings=$((plan_warnings + 1))
    else
        log_error "$message"
        errors=$((errors + 1))
    fi
}

# 1. OS verification
if [ -f /etc/os-release ]; then
    if ! grep -q 'VERSION_ID="26\.04"' /etc/os-release || ! grep -q '^ID=ubuntu' /etc/os-release; then
        log_error "This system is not Ubuntu Server 26.04 LTS"
        errors=$((errors + 1))
    else
        log_info "OS check ok: Ubuntu Server 26.04"
    fi
else
    log_error "/etc/os-release missing"
    errors=$((errors + 1))
fi

# 2. Architecture
arch="$(uname -m)"
case "$arch" in
    x86_64|aarch64) log_info "Architecture ok: $arch" ;;
    *) log_error "Unsupported architecture: $arch"; errors=$((errors + 1)) ;;
esac

# 3. Internet connectivity (runtime precondition)
# We probe HTTP instead of ICMP because many networks block ping while still
# allowing apt to fetch packages, and we try every mirror configured in
# /etc/apt rather than a single canonical hostname — a transient DNS failure
# for archive.ubuntu.com must not block a run whose mirror is, say,
# nl.archive.ubuntu.com.
preflight_http_reachable() {
    local url="$1"
    local code=""
    if command -v curl >/dev/null 2>&1; then
        code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null)" || true
    elif command -v wget >/dev/null 2>&1; then
        wget -q --spider --timeout=5 --tries=1 "$url" 2>/dev/null && code="200" || code="000"
    else
        return 2
    fi
    [ -n "$code" ] && [ "$code" != "000" ]
}

preflight_apt_mirror_urls() {
    local f line word
    local hosts=()

    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [ -f "$f" ] || continue
        while read -r line; do
            case "$line" in
                "deb "*|"deb-src "*) ;;
                *) continue ;;
            esac
            for word in $line; do
                case "$word" in
                    http://*|https://*) hosts+=("$word"); break ;;
                esac
            done
        done < "$f"
    done

    for f in /etc/apt/sources.list.d/*.sources; do
        [ -f "$f" ] || continue
        while read -r line; do
            case "$line" in
                "URIs:"*)
                    for word in ${line#URIs:}; do
                        case "$word" in
                            http://*|https://*) hosts+=("$word") ;;
                        esac
                    done
                    ;;
            esac
        done < "$f"
    done

    if [ "${#hosts[@]}" -eq 0 ]; then
        printf '%s\n' \
            "http://archive.ubuntu.com" \
            "http://security.ubuntu.com"
    else
        printf '%s\n' "${hosts[@]}" \
            | awk -F/ 'NF>=3 {print $1"//"$3}' \
            | sort -u
    fi
}

connectivity_ok=0
connectivity_tried=()
while IFS= read -r url; do
    connectivity_tried+=("$url")
    if preflight_http_reachable "$url"; then
        log_info "Internet connectivity ok ($url reachable)"
        connectivity_ok=1
        break
    fi
done < <(preflight_apt_mirror_urls)

if [ "$connectivity_ok" -eq 0 ]; then
    if [ "${#connectivity_tried[@]}" -eq 0 ]; then
        preflight_runtime_fail "Cannot test connectivity (no curl or wget available)"
    else
        preflight_runtime_fail "Cannot reach any apt mirror over HTTP (tried: ${connectivity_tried[*]}) — apt will fail"
    fi
fi

# 4. APT lock check (runtime precondition)
if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
    preflight_runtime_fail "Another process holds the apt lock (/var/lib/dpkg/lock-frontend)"
else
    log_info "APT lock ok"
fi

# 5. Disk space (root partition >=5 GB free) — runtime precondition
free_gb="$(df -BG --output=avail / | tail -n1 | tr -d 'G ')"
if [ -n "$free_gb" ] && [ "$free_gb" -lt 5 ]; then
    preflight_runtime_fail "Root partition has only ${free_gb}GB free (need >=5GB)"
else
    log_info "Disk space ok: ${free_gb}GB free on /"
fi

# 6. Required commands (only those essential for preflight itself; ip/ping are installed by 05-packages)
missing=()
for cmd in apt-get awk grep sed; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ "${#missing[@]}" -gt 0 ]; then
    log_error "Missing required commands: ${missing[*]}"
    errors=$((errors + 1))
fi

# 7. Defense-in-depth: revalidate config
config_validate || errors=$((errors + 1))

if [ "$errors" -gt 0 ]; then
    log_error "Preflight failed with $errors error(s)"
    exit 1
fi

if [ "$PLAN_MODE" = "1" ]; then
    if [ "$plan_warnings" -gt 0 ]; then
        log_warn "PLAN: preflight passed with $plan_warnings runtime warning(s) — fix before a real run"
    else
        log_info "PLAN: preflight checks all passed"
    fi
fi

log_info "Preflight checks passed"
