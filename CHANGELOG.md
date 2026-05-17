# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Releases

## 1.1.9 – 2026-05-17

### Fixed
- **Plan Mode Credential Validation**
  - Fixed toolkit failing when running `./main.sh --plan` without credentials configured
  - Plan mode is read-only and should not require admin user credentials
  - Validation now only applies during actual execution mode, not when auditing changes
  - Allows users to preview toolkit changes without configuring credentials first

## 1.1.8 – 2026-05-15

### Fixed
- **SECURITY: Command Injection in Password Setup**
  - Fixed shell injection vulnerability in admin user password handling
  - Removed unsafe bash -c wrapper that allowed variable expansion attacks
  - Changed to safe stdin piping: `echo $user:$pass | chpasswd`
  - Prevents malicious shells characters in passwords from executing
  - **Impact:** Critical security fix - prevents privilege escalation

- **SECURITY: Unquoted Variable in Network Connectivity Check**
  - Added proper quoting around $target_ip variable in bash -c
  - Prevents word-splitting and command injection in ping command
  - Example: IP with spaces/pipes would expand without quotes
  - **Impact:** Critical security fix - prevents arbitrary command execution

- **SECURITY: Exit Code Handling in run_quiet()**
  - Explicitly preserve and return exit codes from suppressed commands
  - Critical for proper error handling with 'set -e'
  - Prevents silent failures that could mask serious errors
  - **Impact:** Essential for robustness - commands no longer silently fail

- **Version Check Bot Intelligence**
  - Fixed CI bot to intelligently handle CHANGELOG updates
  - When VERSION is updated: Checks for new version section (no [Unreleased] needed)
  - When VERSION is unchanged: Recommends [Unreleased] section
  - Eliminates false positive bot recommendations on version-bumped PRs

- **Auto-Detect Network Interface**
  - Network interface name now auto-detected and shown as default
  - Automatically finds first active interface (excluding loopback)
  - Falls back to common names (eth0, enp0s3, ens3) if detection fails
  - Much better UX: users see their actual interface instead of generic "ens3"
  - Works seamlessly across different environments (VMs, bare metal, cloud)

- **Service Verification Check in Cleanup Module**
  - Fixed systemctl service unit verification that was unreliable
  - `systemctl list-unit-files` doesn't reliably indicate unit existence
  - Changed to use `systemctl show` with LoadState check instead
  - Ensures accurate detection of available services

- **Cleanup Feedback Missing**
  - Added info-level log message after apt autoremove/clean completion
  - Provides clear feedback that cleanup operation succeeded
  - Improves user visibility into module progress

- **Duplicate Completion Summary**
  - Removed duplicate module list from 99-cleanup module output
  - Final summary is now only shown once by main.sh at the end
  - Eliminates redundant output and cleaner final display

- **Enhanced Module Execution Summary**
  - Added column headers (Module, Completed At, Duration)
  - Execution time calculated for each module
  - Total execution time displayed at end
  - Better formatting for at-a-glance performance metrics

### Changed
- **Consistent Boolean Question Format**
  - All yes/no questions now use (true/false) format
  - Standardized format across USE_DHCP, AUTO_SECURITY_UPDATES, and SEND_TEST_MAIL
  - Simpler validation and more consistent user experience
  - Matches environment variable values

- **Disk Usage Alert Threshold Simplified**
  - Removed interactive question for disk usage threshold
  - Now uses fixed default value of 85%
  - Reduces setup configuration steps
  - Can still be customized by editing config file if needed

- **Project Language Changed to English**
  - All interactive prompts and user-facing messages translated from Dutch to English
  - Interactive setup questionnaire now fully in English
  - Module selection menu and feedback messages in English
  - Configuration creation messages in English
  - Default system locale changed from `nl_NL.UTF-8` to `en_US.UTF-8`
  - Better support for international users and global deployments

### Added
- **Silent Command Execution Helper**
  - New `run_quiet()` function in `lib/log.sh` for executing commands without terminal output
  - Suppresses stdout/stderr of system commands (apt-get, systemctl, etc.) to keep terminal clean
  - Only toolkit logs (green text) shown on terminal; system command output (white text) hidden
  - All output still captured in logfile for debugging and troubleshooting
  - Applied to package management functions (`pkg_install`, `pkg_purge`, `pkg_update`)
  - Applied to ALL system commands across all scripts for consistent clean output

- **Complete Output Suppression**
  - All system commands wrapped with `run_quiet()`:
    - User management (useradd, chpasswd, usermod)
    - Network configuration (hostname, netplan, ip, ss, ufw)
    - System settings (timedatectl, locale, chronyc, sysctl)
    - Service management (systemctl)
    - Firewall and kernel (grub, augenrules)
    - Package cleanup (apt-get autoremove, apt-get clean)
  - Clean terminal with ONLY green toolkit logs
  - Exit codes and command logic fully preserved
  - Full output still available in logfile for troubleshooting

### Changed
- **Static IP Address Default Updated**
  - `IP_ADDRESS` default changed from `192.168.1.10` to `192.168.1.100`
  - Better default allocation pattern for typical gateway (192.168.1.1) scenarios
  - Applied to interactive setup and configuration defaults

- **DHCP Now Default Network Configuration**
  - `USE_DHCP` default changed from `false` to `true`
  - Interactive setup now defaults to DHCP for network configuration
  - More suitable for cloud and automated deployment environments
  - Static IP still available as an option during setup

- **Debug Level Now Default for All Operations**
  - Removed debug level question from interactive setup (no longer user-configurable)
  - `TOOLKIT_LOG_LEVEL` default changed from `info` to `debug` globally
  - All scripts and processes run in debug mode by default
  - Ensures comprehensive logging and debugging information is always available
  - Simplifies setup flow by removing configuration question

### Fixed
- **Admin User Question Always Asked**
  - Removed conditional skip that prevented admin user question from being asked on subsequent runs
  - Admin configuration question now always appears, allowing users to reconfigure settings
  - Previously, selecting "skip" in the first run would cache the setting, preventing the question from appearing in future runs
  
- **Module Dependency DAG Optimization**
  - Fixed overly restrictive linear dependency chain where each module depended on the previous one
  - Corrected dependencies to only enforce actual requirements:
    - `04-system-settings` now depends on `01-base-config` (was `03-network-hardening`)
      Timezone, locale, and NTP configuration don't require network hardening
    - `05-packages` now depends on `01-base-config` (was `04-system-settings`)
      Package installation only requires system update, not timezone/locale setup
    - `07-monitoring` now depends on `05-packages` (was `06-hardening`)
      Monitoring tools only need packages installed, not kernel hardening
  - Enables parallel execution of independent modules, improving toolkit efficiency
  - Maintains correct ordering constraints while removing unnecessary serialization

## 1.1.7 – 2026-05-15

### Added
- **Cascade Deselect for Module Dependencies**
  - When a user disables a module that other modules depend on, those
    dependent modules are automatically deselected
  - Prevents invalid module combinations where selected modules have
    unmet dependencies
  - Each cascaded deselection is logged with explanation
  - Recursive: if module A depends on B, and B depends on C, disabling C
    also disables B and A

### Changed
- **Module Selection Menu Layout**
  - Removed blank line after "Current selection:" header
  - Removed empty description line (MODULE_DESC field currently unused)
  - Combined module name and dependencies on a single aligned line
  - Format: `N) [x] module-name             (requires: dependency)`
  - Cleaner, more compact display

### Fixed
- **Module Selection Menu Display Bug (complete fix)**
  - Fixed main menu not waiting for user input and closing immediately
  - **Root cause #1:** `questionnaire_ask_modules()` was called via process
    substitution `< <(questionnaire_ask_modules)` in `main.sh`. Bash
    redirects stdin for the subshell in process substitution, causing
    `read` inside the function to fail
  - **Root cause #2:** `((index++))` returned exit code 1 when `index` was 0
    (post-increment returns the OLD value, and `set -e` triggers when
    arithmetic evaluates to 0). This was previously hidden because the
    failure only killed the process-substitution subshell
  - **Fix #1:** Refactored to populate the global `SELECTED_MODULES`
    array directly; `main.sh` now calls the function without process
    substitution so `read` can access the terminal
  - **Fix #2:** Replaced `((index++))` with `index=$((index + 1))`
    which always returns exit code 0
  - **Fix #3:** Added graceful fallback if `read` fails (non-interactive
    environment) — function continues with current selection instead of
    crashing the script
  - **Fix #4:** Earlier attempt (1.1.6 partial) added `/dev/tty` read for
    terminal access; superseded by direct function call approach
  - Menu now displays properly and correctly waits for user input

- **Metadata Field Parser Bug (CRITICAL)**
  - Fixed metadata parsing to properly trim leading spaces from `DEPENDS`, `DESC`, `IDEMPOTENT`, and `DESTRUCTIVE` fields
  - Previously `${field# }` only removed the first space, leaving multiple leading spaces intact
  - This caused cascade deselect and dependency checking to fail because grep patterns wouldn't match
  - Changed to `${field#"${field%%[^ ]*}"}` to remove all leading whitespace
  - **Impact:** Cascade deselect and cascade auto-select features now work correctly
  - Fixes dependency resolution in questionnaire menus

## 1.1.6 – 2026-05-15

### Fixed
- **Module Selection Menu Display Bug (second partial attempt)**
  - Tried reading from `/dev/tty` to access the terminal directly for menu input
  - Worked around the immediate symptom but did not address the underlying
    process-substitution / `set -e` root causes
  - Superseded by the complete fix in 1.1.7

## 1.1.5 – 2026-05-15

### Fixed
- **Module Selection Menu Display Bug (first partial attempt)**
  - `questionnaire_ask_modules()` was sending menu UI messages to stdout
  - These messages were captured by the module selection read loop, breaking the interactive menu
  - All informational output now correctly redirected to stderr
  - Note: this fix proved insufficient; further root causes addressed in 1.1.6 and 1.1.7

## 1.1.4 – 2026-05-15

### Fixed
- **Dependency Parser Bug**
  - Fixed invalid `DEPENDS: none` syntax in `00-preflight.sh` module header
  - Parser now correctly recognizes empty `DEPENDS:` field for modules with no dependencies
  - Resolves "missing module: none" and "dependency cycle detected" errors
  - Allows `--list`, `--plan`, `--dry-run` flags to work correctly

## 1.1.3 – 2026-05-15

### Fixed
- **`--dry-run` Flag Consistency**
  - Ensured `TOOLKIT_PLAN_MODE` consistency for `--dry-run` mode in `main.sh`
  - Aligns dry-run behaviour with plan mode expectations

### Changed
- **Documentation Reorganisation**
  - Reorganised README sections for better logical flow
  - Reorganised CONTRIBUTING sections for better learning flow
  - Removed deprecated flags from README documentation (`--retry`, `--only`, `--skip`)
  - Added missing `-v`/`--version` flag to README
- Updated copyright year from 2025 to 2026 across the project

## 1.1.2 – 2026-05-14

### Fixed
- **Module Discovery Bug**
  - Fixed `discover_modules()` incorrectly discovering `setup-hooks.sh` as a configuration module
  - `setup-hooks.sh` (development utility) was being executed during toolkit runs, including `--plan` mode
  - Restricted module discovery pattern to `[0-9][0-9]-*.sh` to match only numbered modules (00-99 range)
  - Aligns with documented module naming convention

## 1.1.1 – 2026-05-14

### Fixed
- **Main Script Configuration Handling**
  - `--plan` and `--dry-run` flags now work without pre-existing config file (use sensible defaults)
  - Fixed config file error that blocked preview commands from running
  - Improved error handling when config is missing in non-interactive modes

- **Module Selection Order**
  - Module selection menu now appears BEFORE configuration questions (improved UX)
  - Users can see which modules they're configuring before answering config prompts
  - Better intent and clearer flow for interactive setup

- **Configuration Question Filtering**
  - Config questions now filtered by selected modules
  - Email/SMTP questions only shown if `08-mail-alerting` module is selected
  - Eliminates irrelevant configuration prompts for unselected functionality
  - Improved user experience for partial toolkit configurations

### Changed
- `questionnaire_run()` now accepts optional selected modules parameter
- Config loading flow refactored for better handling of plan/dry-run modes
- Enhanced sensible defaults for headless/automated deployments

## 1.1.0 – 2026-05-14

### Added
- **Interactive Module Selection Questionnaire**
  - New `questionnaire_ask_modules()` function in `lib/questionnaire.sh`
  - Checkbox-style menu for intuitive module selection at startup
  - Automatic dependency resolution with clear feedback on auto-selected modules
  - Warning system for broken dependencies (when disabling modules that others depend on)
  - Support for plan mode and non-interactive mode

### Changed
- **Module Selection**: Replaced command-line flags with interactive questionnaire
  - Removed `--skip=<modules>` flag (use questionnaire instead)
  - Removed `--only=<module>` flag (use questionnaire instead)
  - Users now select modules interactively instead of remembering module names and using flags
  - `--retry=<module>` flag still works (skips questionnaire, selects all modules)

### Backward Compatibility
- `--resume`, `--force` flags still work as before
- `TOOLKIT_NONINTERACTIVE=1` skips questionnaire and enables all modules
- `TOOLKIT_PLAN_MODE=1` skips questionnaire and shows all modules

## 1.0.2 – 2026-05-13

### Changed
- **Code Quality Refactoring**: Introduced `lib/plan.sh` with `plan_action()` helper function
  - Eliminated 17+ instances of boilerplate PLAN_MODE checking patterns across modules
  - Reduces code duplication by ~50 lines
  - Centralizes plan-mode logic for easier maintenance and future updates
  - Refactored modules: 01-base-config, 02-ip-config, 03-network-hardening, 08-mail-alerting

### Fixed
- **Language Consistency**: Removed Dutch language strings from 08-mail-alerting.sh
  - All logging and email strings now consistently in English
  - Improves i18n compatibility for future localization efforts
- **DNS Configuration**: Added bounds checking for DNS_SERVERS array in 02-ip-config.sh
  - Now warns if DNS_SERVERS is empty instead of silently continuing

## 1.0.1 – 2026-05-13

### Changed
- Tests now run **only** with explicit `--test` flag
  - Tests no longer run automatically with `--plan` or `--dry-run` flags
  - Tests no longer run when main.sh is executed without flags (default behavior)
  - This allows `--plan` and `--dry-run` to complete faster for quick audits

### Fixed
- Bug fixes and corrections

### Deprecated
- Features marked for removal in future versions

### Removed
- Removed features or modules

### Security
- Security-related fixes

## 1.0.0 – 2026-05-13

### Added
- **Initial stable release** of Ubuntu Server 26.04 LTS Configuration Toolkit
- Modular bash toolkit for end-to-end system configuration:
  - Preflight checks (OS validation, disk space, internet, apt locks)
  - Base configuration (apt upgrade, sudo user, unattended-upgrades)
  - IP/network configuration with Netplan support
  - Timezone and NTP configuration (chrony)
  - Kernel hardening and AppArmor setup
  - Auditd audit logging
  - Mail relay with Postfix
  - System monitoring with collectd
  - Log aggregation with Rsyslog
  - Service cleanup and optimization
- Comprehensive module system with:
  - Automatic dependency resolution (DAG validation)
  - Idempotency guarantees (safe to run multiple times)
  - Plan mode for dry-run audits (`--plan` flag)
  - Syntax validation and linting via ShellCheck
  - BATS unit test suite
  - Full state tracking and recovery
- Rich CLI with flags:
  - `--list` - module discovery
  - `--plan` - read-only audit
  - `--dry-run` - syntax validation
  - `--resume` - recovery from failures
  - `--force` - re-run all modules
  - `--retry=<module>` - retry single module
  - `--only=<module>` - run single module
  - `--skip=<modules>` - skip specific modules
  - `--test` - full test suite
  - `--ignore-errors` - non-critical error recovery
  - `--version` / `-v` - display toolkit version
- Interactive questionnaire for initial setup
- State file tracking for fault recovery (`/var/log/toolkit-setup/.state`)
- Comprehensive logging to `/var/log/toolkit-setup/toolkit-setup.log`
- Git-safe configuration (credentials excluded via .gitignore)
- **Semantic versioning** support with:
  - `VERSION` file tracking current release
  - `lib/version.sh` helper library
  - Version display in CLI and logs
  - Release process documentation

### Documentation
- Complete README with quickstart and module reference
- CLAUDE.md with architectural guidelines
- CONTRIBUTING.md with development conventions and release process
- Extensive inline code documentation
- Helper library quick reference

### Testing
- Syntax validation with `bash -n`
- ShellCheck linting (SC1091, SC2034 exclusions)
- BATS unit tests for common.sh and idempotency
- Structural validation (module headers, DAG cycles, dependencies)
- Local testing instructions in README and CONTRIBUTING

### Project Governance
- MIT License
- Pre-commit hooks for changelog enforcement
- Semantic versioning with documented release process
- Comprehensive error recovery and user guidance
