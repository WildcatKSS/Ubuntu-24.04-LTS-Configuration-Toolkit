#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# lib/jail.sh — Fail2ban jail configuration helpers

# Validate fail2ban jail configuration file syntax
# Usage: validate_jail_config "/etc/fail2ban/jail.local"
# Returns 0 if valid, 1 if invalid (prints errors to stderr)
validate_jail_config() {
    local jail_file="$1"

    if [ ! -f "$jail_file" ]; then
        log_error "Jail config file not found: $jail_file"
        return 1
    fi

    # Check if fail2ban-client is available
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        log_warn "fail2ban-client not available, skipping syntax validation"
        return 0
    fi

    # Use fail2ban-client to validate (dry-run mode)
    if fail2ban-client -d -c "$jail_file" >/dev/null 2>&1; then
        return 0
    else
        # If validation fails, try to give more detail
        local errors
        errors=$(fail2ban-client -d -c "$jail_file" 2>&1 | grep -i "error\|invalid" || echo "Unknown error")
        log_error "Jail configuration invalid: $errors"
        return 1
    fi
}

# Test if a jail section exists in config (without requiring fail2ban running)
# Usage: jail_section_exists "/etc/fail2ban/jail.local" "sshd"
# Returns 0 if section exists, 1 if not
jail_section_exists() {
    local jail_file="$1"
    local section="$2"

    if grep -q "^\[$section\]" "$jail_file" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Get list of jails defined in a jail config file
# Usage: jail_list_sections "/etc/fail2ban/jail.local"
# Returns: one jail name per line
jail_list_sections() {
    local jail_file="$1"

    grep "^\[" "$jail_file" 2>/dev/null | sed 's/\[\(.*\)\]/\1/' | grep -v "^DEFAULT$"
}

# Check if a specific port is in a jail definition
# Usage: jail_port_in_section "/etc/fail2ban/jail.local" "postfix-sasl" "smtp"
# Returns 0 if port found in jail, 1 if not
jail_port_in_section() {
    local jail_file="$1"
    local section="$2"
    local port="$3"

    # Extract jail section and check for port definition
    awk "/^\[$section\]/,/^\[/ {print}" "$jail_file" 2>/dev/null | \
        grep -q "port.*=.*$port" && return 0
    return 1
}

# Verify ports match between two jails
# Usage: jail_ports_match "/etc/fail2ban/jail.local" "postfix-sasl" "recidive"
# Returns 0 if postfix ports are in recidive action, 1 otherwise
jail_ports_match() {
    local jail_file="$1"
    local source_jail="$2"
    local target_jail="$3"

    # Extract ports from source jail
    local source_ports
    source_ports=$(awk "/^\[$source_jail\]/,/^\[/ {if (/^port/) print}" "$jail_file" 2>/dev/null | \
        sed 's/port.*=//;s/[[:space:]]*//g')

    if [ -z "$source_ports" ]; then
        log_warn "No ports found in $source_jail jail"
        return 1
    fi

    # Check if target jail contains source ports
    local target_ports
    target_ports=$(awk "/^\[$target_jail\]/,/^\[/ {if (/^action.*port=/) print}" "$jail_file" 2>/dev/null)

    # Simple check: target should contain all source port names (comma-separated)
    local port_ok=1
    while IFS=',' read -r port; do
        port=$(echo "$port" | xargs)  # trim whitespace
        if ! echo "$target_ports" | grep -q "$port"; then
            log_warn "Port '$port' from $source_jail not found in $target_jail"
            port_ok=0
        fi
    done <<< "$source_ports"

    return $((1 - port_ok))
}

# Validate common fail2ban configuration patterns
# Usage: validate_jail_patterns "/etc/fail2ban/jail.local"
# Returns 0 if patterns look correct, 1 if issues found
validate_jail_patterns() {
    local jail_file="$1"
    local issues=0

    # Check for required [DEFAULT] section
    if ! jail_section_exists "$jail_file" "DEFAULT"; then
        log_warn "Missing [DEFAULT] section in $jail_file"
        issues=$((issues + 1))
    fi

    # Check for orphaned action definitions (lines not in any section)
    if grep -v "^\[" "$jail_file" | grep -q "^action"; then
        log_warn "Orphaned action definition found outside a jail section"
        issues=$((issues + 1))
    fi

    # Check for duplicate section names
    local duplicates
    duplicates=$(grep "^\[" "$jail_file" | sort | uniq -d)
    if [ -n "$duplicates" ]; then
        log_warn "Duplicate jail sections found: $duplicates"
        issues=$((issues + 1))
    fi

    return $((issues > 0 ? 1 : 0))
}
