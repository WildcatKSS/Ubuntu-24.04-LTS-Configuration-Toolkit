#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# lib/service.sh — Service management helpers

# Check if a systemd service is currently running
# Usage: service_is_running "ssh.service" || service_is_running "sshd.service"
# Returns 0 if service is running, 1 if not
service_is_running() {
    local service="$1"
    systemctl list-units --type=service --state=running 2>/dev/null | grep -q "$(basename "$service" .service)"
}

# Check if any of multiple services are running
# Usage: service_any_running "ssh.service" "sshd.service"
# Returns 0 if any service is running, 1 if none are running
service_any_running() {
    local service
    for service in "$@"; do
        if service_is_running "$service"; then
            return 0
        fi
    done
    return 1
}

# Get list of all running services matching a pattern
# Usage: service_list_running "postfix" "mail"
# Returns matching service names, one per line
service_list_running() {
    local pattern
    systemctl list-units --type=service --state=running --output=json 2>/dev/null | \
        grep -o '"unit":"[^"]*"' | cut -d'"' -f4 | while read -r unit; do
            for pattern in "$@"; do
                if [[ "$unit" == *"$pattern"* ]]; then
                    echo "$unit"
                    break
                fi
            done
        done
}

# Check if a service is enabled (starts on boot)
# Usage: service_is_enabled "ssh.service"
# Returns 0 if enabled, 1 if not
service_is_enabled() {
    local service="$1"
    systemctl is-enabled "$service" >/dev/null 2>&1
}
