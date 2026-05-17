#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
#
# lib/questionnaire.sh — Interactive questionnaire for all toolkit setup prompts
#
# This module collects all user input upfront, allowing the toolkit to run
# unattended after the initial questionnaire. All answers are stored as
# environment variables that persist across module execution.
#
# Usage: source this file and call questionnaire_run to collect all answers
#
# Environment variables set by this questionnaire:
#   ADMIN_MODE_CREATE_USER      "yes" to create new user, "no" to change password, "skip" to leave unchanged
#   ADMIN_USER                  Username for new admin user or existing user
#   ADMIN_PASSWORD              Password for admin user
#   TOOLKIT_LOG_LEVEL           Log level (debug|info|warn|error)
#   HOSTNAME                    System hostname
#   NETWORK_INTERFACE           Network interface name
#   USE_DHCP                    "true" or "false" for DHCP vs static IP
#   IP_ADDRESS                  Static IP address (if not using DHCP)
#   PREFIX_LENGTH               Network prefix length (if not using DHCP)
#   GATEWAY                     Default gateway (if not using DHCP)
#   DNS_SERVERS                 Space-separated DNS servers (if not using DHCP)
#   TIMEZONE                    System timezone
#   LOCALE                      System locale
#   EMAIL_TO                    Email address for alerts
#   SMTP_RELAY_HOST             SMTP relay hostname
#   SMTP_RELAY_PORT             SMTP relay port
#   DISK_ALERT_THRESHOLD        Disk usage alert threshold percentage
#   AUTO_SECURITY_UPDATES       "true" or "false" for unattended upgrades
#   SEND_TEST_MAIL              "yes" to send a test mail after postfix setup

# detect_network_interface
# Auto-detect the first active network interface (excluding lo)
detect_network_interface() {
    local iface
    # Try to get first non-loopback interface from ip link
    iface=$(ip link show 2>/dev/null | grep -E "^[0-9]+:" | grep -v "lo:" | head -1 | sed 's/^[0-9]*: \([^:]*\).*/\1/')

    # Fallback to common names if detection fails
    if [ -z "$iface" ]; then
        if [ -d /sys/class/net/ens3 ]; then
            iface="ens3"
        elif [ -d /sys/class/net/eth0 ]; then
            iface="eth0"
        elif [ -d /sys/class/net/enp0s3 ]; then
            iface="enp0s3"
        else
            iface="ens3"  # Default fallback
        fi
    fi
    echo "$iface"
}

# config_create_defaults
# Set sensible default environment variables for plan/dry-run modes
# when config file doesn't exist yet.
config_create_defaults() {
    export ADMIN_MODE_CREATE_USER="yes"
    export ADMIN_USER="admin"
    export ADMIN_PASSWORD="changeme"
    export TOOLKIT_LOG_LEVEL="debug"
    export NETWORK_INTERFACE="$(detect_network_interface)"
    export USE_DHCP="true"
    export IP_ADDRESS="192.168.1.100"
    export PREFIX_LENGTH="24"
    export GATEWAY="192.168.1.1"
    export DNS_SERVERS="1.1.1.3 1.0.0.3"
    export HOSTNAME="server.local.lan"
    export TIMEZONE="Europe/Amsterdam"
    export LOCALE="nl_NL.UTF-8"
    export EMAIL_TO="admin@example.com"
    export SMTP_RELAY_HOST="smtp.example.com"
    export SMTP_RELAY_PORT="587"
    export DISK_ALERT_THRESHOLD="85"
    export AUTO_SECURITY_UPDATES="true"
    export SEND_TEST_MAIL="no"
}

# questionnaire_prompt_string <prompt> [default]
# Generic string prompt. Returns the answer or default if empty.
questionnaire_prompt_string() {
    local prompt="$1"
    local default="$2"
    local answer

    if [ -n "${default:-}" ]; then
        printf '%s [%s]: ' "$prompt" "$default" >&2
    else
        printf '%s: ' "$prompt" >&2
    fi

    read -r answer
    answer="${answer:-$default}"
    echo "$answer"
}

# questionnaire_prompt_password <prompt>
# Silent password input with confirmation.
questionnaire_prompt_password() {
    local prompt="$1"

    while true; do
        printf '%s: ' "$prompt" >&2
        read -rs password1
        echo >&2

        printf 'Confirm %s: ' "$(echo "$prompt" | tr '[:upper:]' '[:lower:]')" >&2
        read -rs password2
        echo >&2

        if [ "$password1" = "$password2" ] && [ -n "$password1" ]; then
            echo "$password1"
            return 0
        fi

        log_warn "Passwords do not match or empty. Try again."
    done
}

# questionnaire_run [selected_modules_csv]
# Main questionnaire: prompts for configuration needed by selected modules.
# selected_modules_csv: comma-separated module names (e.g., "01-base-config,02-ip-config")
#                       If provided, only asks for config relevant to those modules
questionnaire_run() {
    local selected_modules="${1:-}"

    if [ "${TOOLKIT_PLAN_MODE:-0}" = "1" ] || [ "${TOOLKIT_NONINTERACTIVE:-0}" = "1" ]; then
        log_info "Skipping questionnaire (plan mode or non-interactive)"
        return 0
    fi

    echo
    log_info "=== Ubuntu Toolkit Interactive Setup ==="
    echo
    echo "This script configures a fresh Ubuntu Server 26.04 LTS installation end-to-end."
    echo "Answer the questions by section. Press Enter to accept the default value."
    echo

    # -------------------------------------------------------------------------
    # Section 1: Admin User
    # -------------------------------------------------------------------------
    log_info "Section 1: Administrator (sudo user)"
    echo
    echo "The toolkit creates or configures a user with sudo privileges."
    echo "This account is used for management after installation."
    echo "Root login via SSH will be disabled after installation, so"
    echo "ensure this user is set up correctly before proceeding."
    echo

    log_info "What would you like to do with the administrator?"
    echo "  1. Create new sudo user"
    echo "  2. Change password for existing sudo user"
    echo "  3. Skip (no changes to sudo user)"
    echo

    while true; do
        printf 'Choose option (1, 2 or 3): ' >&2
        read -r user_choice
        case "$user_choice" in
            1)
                export ADMIN_MODE_CREATE_USER="yes"
                log_info "Mode: Create new sudo user"
                echo

                ADMIN_USER=$(questionnaire_prompt_string "Username for new administrator" "admin")
                export ADMIN_USER

                if system_user_exists "$ADMIN_USER"; then
                    log_warn "User '$ADMIN_USER' already exists!"
                    if system_confirm "Change password for this user?" no; then
                        export ADMIN_MODE_CREATE_USER="no"
                        break
                    else
                        continue
                    fi
                fi

                ADMIN_PASSWORD=$(questionnaire_prompt_password "Password for $ADMIN_USER")
                export ADMIN_PASSWORD
                break
                ;;
            2)
                export ADMIN_MODE_CREATE_USER="no"
                log_info "Mode: Change password for existing user"
                echo

                while true; do
                    ADMIN_USER=$(questionnaire_prompt_string "Username of existing sudo user" "root")
                    export ADMIN_USER

                    if system_user_exists "$ADMIN_USER"; then
                        break
                    fi
                    log_warn "User '$ADMIN_USER' does not exist"
                done

                ADMIN_PASSWORD=$(questionnaire_prompt_password "New password for $ADMIN_USER")
                export ADMIN_PASSWORD
                break
                ;;
            3)
                export ADMIN_MODE_CREATE_USER="skip"
                log_info "Mode: Skip sudo user configuration"
                break
                ;;
            *)
                log_warn "Invalid choice. Enter 1, 2 or 3."
                ;;
        esac
    done

    echo

    # -------------------------------------------------------------------------
    # Section 2: System Configuration
    # -------------------------------------------------------------------------
    log_info "Section 2: System settings"
    echo
    echo "Basic server identity: hostname, timezone and language."
    echo "The hostname is used in email notifications and log entries."
    echo "The timezone determines local time for cron jobs and logfiles."
    echo

    HOSTNAME=$(questionnaire_prompt_string "Hostname of the server" "server.local.lan")
    export HOSTNAME

    TIMEZONE=$(questionnaire_prompt_string "Timezone" "Europe/Amsterdam")
    export TIMEZONE

    LOCALE=$(questionnaire_prompt_string "System language (locale)" "en_US.UTF-8")
    export LOCALE

    echo

    # -------------------------------------------------------------------------
    # Section 3: Network Configuration
    # -------------------------------------------------------------------------
    log_info "Section 3: Network configuration"
    echo
    echo "Configuration of the primary network interface via Netplan."
    echo "Choose DHCP if the network automatically assigns an IP address."
    echo "Choose static if the server must always have the same IP address"
    echo "(recommended for servers that must be reachable at a fixed address)."
    echo "Warning: incorrect network configuration can break SSH connection."
    echo "The toolkit automatically backs up the existing Netplan configuration."
    echo

    NETWORK_INTERFACE=$(questionnaire_prompt_string "Network interface name" "${NETWORK_INTERFACE:-ens3}")
    export NETWORK_INTERFACE

    USE_DHCP=$(questionnaire_prompt_string "Use DHCP? (true/false)" "true")
    export USE_DHCP

    if [ "$USE_DHCP" = "false" ]; then
        IP_ADDRESS=$(questionnaire_prompt_string "Static IP address" "192.168.1.100")
        export IP_ADDRESS

        PREFIX_LENGTH=$(questionnaire_prompt_string "Network prefix length (e.g. 24 for /24)" "24")
        export PREFIX_LENGTH

        GATEWAY=$(questionnaire_prompt_string "Default gateway" "192.168.1.1")
        export GATEWAY

        DNS_SERVERS=$(questionnaire_prompt_string "DNS servers (space-separated)" "1.1.1.3 1.0.0.3")
        export DNS_SERVERS
    fi

    echo

    # -------------------------------------------------------------------------
    # Section 4: Email and Alerts (only if mail-alerting module is selected)
    # -------------------------------------------------------------------------
    if [[ "$selected_modules" == *"08-mail-alerting"* ]] || [ -z "$selected_modules" ]; then
        log_info "Section 4: Email and alerts"
    echo
    echo "The toolkit configures Postfix as an SMTP relay for email notifications."
    echo "You will receive daily reports on server status and immediate"
    echo "alerts for high disk usage or failed services."
    echo "Enter the address of your own SMTP relay (e.g. your mail provider or"
    echo "an internal mail server). Store authentication credentials in"
    echo "/etc/postfix/sasl_passwd after installation."
    echo

    EMAIL_TO=$(questionnaire_prompt_string "Email address for alerts" "admin@example.com")
    export EMAIL_TO

    SMTP_RELAY_HOST=$(questionnaire_prompt_string "SMTP relay hostname" "smtp.example.com")
    export SMTP_RELAY_HOST

    SMTP_RELAY_PORT=$(questionnaire_prompt_string "SMTP relay port" "587")
    export SMTP_RELAY_PORT

    export DISK_ALERT_THRESHOLD="85"

    echo
    echo "After Postfix installation, a test mail can be sent to"
    echo "$EMAIL_TO to verify the mail relay works correctly."
    echo

    SEND_TEST_MAIL=$(questionnaire_prompt_string "Send test mail after Postfix installation? (true/false)" "false")
    export SEND_TEST_MAIL

        echo
    fi  # end email section

    # -------------------------------------------------------------------------
    # Section 5: Security Updates
    # -------------------------------------------------------------------------
    log_info "Section 5: Security updates"
    echo
    echo "Unattended-upgrades installs security updates automatically,"
    echo "without manual intervention. This keeps the server up-to-date against"
    echo "known vulnerabilities. Only security packages are automatically"
    echo "updated; major version upgrades always require manual action."
    echo

    AUTO_SECURITY_UPDATES=$(questionnaire_prompt_string "Enable automatic security updates? (true/false)" "true")
    export AUTO_SECURITY_UPDATES

    echo
    log_info "Questionnaire complete. Installation will proceed with your settings."
    echo
}

# questionnaire_ask_modules
# Interactive module selection menu with checkbox-style interface.
# Handles dependency resolution and prevents invalid combinations.
# Populates the global SELECTED_MODULES array directly (no stdout capture).
# This avoids process-substitution issues where stdin is disconnected
# from the terminal, which prevented the interactive `read` from working.
# Note: Expects MODULE_PATHS, MODULE_NAME, MODULE_DESC, MODULE_DEPENDS globals from main.sh
# Note: Populates the global SELECTED_MODULES array (declared in main.sh)
questionnaire_ask_modules() {
    SELECTED_MODULES=()

    if [ "${TOOLKIT_PLAN_MODE:-0}" = "1" ] || [ "${TOOLKIT_NONINTERACTIVE:-0}" = "1" ]; then
        log_info "Skipping module selection (plan mode or non-interactive) — enabling all modules"
        local path
        for path in "${MODULE_PATHS[@]}"; do
            SELECTED_MODULES+=("${MODULE_NAME[$path]}")
        done
        return 0
    fi

    echo
    log_info "=== Module Selection ==="
    echo
    echo "Choose which modules you want to enable."
    echo "Modules with dependencies are automatically enabled."
    echo "Enter module numbers (comma-separated) to toggle in/out, e.g.: 1,3,5"
    echo

    declare -g -A QUESTIONNAIRE_SELECTED=()
    declare -a module_list=()
    local index=0
    local path

    for path in "${MODULE_PATHS[@]}"; do
        local short="${MODULE_NAME[$path]}"
        QUESTIONNAIRE_SELECTED[$short]=1
        module_list+=("$short")
    done

    while true; do
        echo "Current selection:"
        index=0
        for short in "${module_list[@]}"; do
            local checkbox="[ ]"
            [ "${QUESTIONNAIRE_SELECTED[$short]:-0}" = "1" ] && checkbox="[x]"
            local deps="${MODULE_DEPENDS[$short]:-}"
            if [ -n "$deps" ]; then
                printf '%d) %s %-25s (requires: %s)\n' "$index" "$checkbox" "$short" "$deps"
            else
                printf '%d) %s %s\n' "$index" "$checkbox" "$short"
            fi
            index=$((index + 1))
        done
        echo
        printf 'Toggle modules (numbers separated by comma), or press Enter to continue: '
        if ! read -r input; then
            log_warn "Could not read from stdin (non-interactive environment?). Continuing with current selection."
            break
        fi
        [ -z "$input" ] && break

        local to_toggle=()
        IFS=',' read -ra to_toggle <<< "$input"

        for num in "${to_toggle[@]}"; do
            num="${num// /}"
            if [ -n "$num" ] && [ "$num" -ge 0 ] 2>/dev/null && [ "$num" -lt "${#module_list[@]}" ] 2>/dev/null; then
                local target="${module_list[$num]}"
                if [ "${QUESTIONNAIRE_SELECTED[$target]:-0}" = "1" ]; then
                    QUESTIONNAIRE_SELECTED[$target]=0
                    log_info "Disabled: $target"
                    questionnaire_check_broken_deps "$target"
                    questionnaire_deselect_dependents "$target"
                else
                    QUESTIONNAIRE_SELECTED[$target]=1
                    log_info "Enabled: $target"
                    questionnaire_auto_select_deps "$target"
                fi
            else
                log_warn "Invalid module number: $num"
            fi
        done
        echo
    done

    for short in "${module_list[@]}"; do
        [ "${QUESTIONNAIRE_SELECTED[$short]:-0}" = "1" ] && SELECTED_MODULES+=("$short")
    done
}

# questionnaire_auto_select_deps <module_short>
# Recursively select all dependencies of a module.
questionnaire_auto_select_deps() {
    local module="$1"
    local deps="${MODULE_DEPENDS[$module]:-}"

    if [ -z "$deps" ]; then
        return 0
    fi

    local dep
    local auto_selected=()
    IFS=',' read -ra dep_array <<< "$deps"

    for dep in "${dep_array[@]}"; do
        dep="${dep// /}"
        [ -z "$dep" ] && continue

        if [ "${QUESTIONNAIRE_SELECTED[$dep]:-0}" != "1" ]; then
            QUESTIONNAIRE_SELECTED[$dep]=1
            auto_selected+=("$dep")
            questionnaire_auto_select_deps "$dep"
        fi
    done

    if [ "${#auto_selected[@]}" -gt 0 ]; then
        log_info "  (automatically selected: ${auto_selected[*]})"
    fi
}

# questionnaire_check_broken_deps <module_short>
# Warn if disabling a module breaks dependencies of other enabled modules.
questionnaire_check_broken_deps() {
    local module="$1"
    local broken=()
    local short

    for short in "${!MODULE_DEPENDS[@]}"; do
        [ "${QUESTIONNAIRE_SELECTED[$short]:-0}" != "1" ] && continue

        local deps="${MODULE_DEPENDS[$short]:-}"
        [ -z "$deps" ] && continue

        if echo ",$deps," | grep -q ",$module,"; then
            broken+=("$short")
        fi
    done

    if [ "${#broken[@]}" -gt 0 ]; then
        log_warn "⚠ Other modules require $module:"
        for short in "${broken[@]}"; do
            log_warn "  - $short"
        done
        log_warn "  These modules cannot work without $module."
    fi
}

# questionnaire_create_config <toolkit_root>
# Generate defaults.conf from questionnaire answers
questionnaire_create_config() {
    local toolkit_root="$1"
    local conf_file="$toolkit_root/config/defaults.conf"

    cat > "$conf_file" <<'EOF'
# Ubuntu Server 26.04 LTS Configuration Toolkit — defaults
# Generated by interactive questionnaire
#
# Variables prompted interactively (or via env var) — NOT in this file:
#   ADMIN_USER, ADMIN_PASSWORD       (script 01)

# ---------------------------------------------------------------------------
# Admin user
# ---------------------------------------------------------------------------
EOF

    # shellcheck disable=SC2129
    echo "ADMIN_MODE_CREATE_USER=\"${ADMIN_MODE_CREATE_USER:-yes}\"" >> "$conf_file"
    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
EOF
    echo "TOOLKIT_LOG_LEVEL=\"${TOOLKIT_LOG_LEVEL:-debug}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
EOF

    echo "NETWORK_INTERFACE=\"${NETWORK_INTERFACE:-ens3}\"" >> "$conf_file"
    echo "USE_DHCP=\"${USE_DHCP:-false}\"" >> "$conf_file"
    echo "IP_ADDRESS=\"${IP_ADDRESS:-192.168.1.100}\"" >> "$conf_file"
    echo "PREFIX_LENGTH=\"${PREFIX_LENGTH:-24}\"" >> "$conf_file"
    echo "GATEWAY=\"${GATEWAY:-192.168.1.1}\"" >> "$conf_file"
    echo "DNS_SERVERS=\"${DNS_SERVERS:-1.1.1.3 1.0.0.3}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# System identity
# ---------------------------------------------------------------------------
EOF

    echo "HOSTNAME=\"${HOSTNAME:-server.local.lan}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Time / NTP
# ---------------------------------------------------------------------------
NTP_SERVERS=(
  "0.pool.ntp.org"
  "1.pool.ntp.org"
  "2.pool.ntp.org"
  "3.pool.ntp.org"
)
FALLBACK_NTP="time.cloudflare.com time.google.com"

EOF

    echo "TIMEZONE=\"${TIMEZONE:-Europe/Amsterdam}\"" >> "$conf_file"
    echo "LOCALE=\"${LOCALE:-en_US.UTF-8}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Email / SMTP relay
# ---------------------------------------------------------------------------
EOF

    echo "EMAIL_TO=\"${EMAIL_TO:-admin@example.com}\"" >> "$conf_file"
    echo "SMTP_RELAY_HOST=\"${SMTP_RELAY_HOST:-smtp.example.com}\"" >> "$conf_file"
    echo "SMTP_RELAY_PORT=\"${SMTP_RELAY_PORT:-587}\"" >> "$conf_file"
    echo "SEND_TEST_MAIL=\"${SEND_TEST_MAIL:-no}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------
EOF

    echo "DISK_ALERT_THRESHOLD=${DISK_ALERT_THRESHOLD:-85}" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Unattended upgrades
# ---------------------------------------------------------------------------
EOF

    echo "AUTO_SECURITY_UPDATES=\"${AUTO_SECURITY_UPDATES:-true}\"" >> "$conf_file"

    chmod 600 "$conf_file"
    log_info "Configuration file created: $conf_file (mode 600)"
}

# questionnaire_deselect_dependents <module_short>
# Recursively deselect all modules that depend on the given module.
questionnaire_deselect_dependents() {
    local module="$1"
    local short

    for short in "${!MODULE_DEPENDS[@]}"; do
        [ "${QUESTIONNAIRE_SELECTED[$short]:-0}" != "1" ] && continue

        local deps="${MODULE_DEPENDS[$short]:-}"
        [ -z "$deps" ] && continue

        if echo ",$deps," | grep -q ",$module,"; then
            QUESTIONNAIRE_SELECTED[$short]=0
            log_info "  (also disabled: $short — it requires $module)"
            questionnaire_deselect_dependents "$short"
        fi
    done
}
