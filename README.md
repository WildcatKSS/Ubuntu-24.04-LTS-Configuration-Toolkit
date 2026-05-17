# Ubuntu Server 26.04 LTS Configuration Toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.1.9-blue)](./VERSION)
[![Ubuntu 26.04 LTS](https://img.shields.io/badge/Ubuntu-26.04%20LTS-orange)](https://releases.ubuntu.com/26.04/)
![Bash 4.0+](https://img.shields.io/badge/bash-4.0+-blue)
[![Tests: BATS](https://img.shields.io/badge/tests-BATS-blue)](./tests/)
![Idempotent](https://img.shields.io/badge/idempotent-yes-brightgreen)
![ShellCheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)
![Status](https://img.shields.io/badge/status-active-success)

A modular bash toolkit that takes a freshly installed Ubuntu Server 26.04 LTS system
and configures it from bare to production-ready in one run: network, hardening,
monitoring, mail relay and alerting.

---

## Quickstart

Install
```bash
git clone https://github.com/WildcatKSS/Ubuntu-26.04-LTS-Configuration-Toolkit
cd Ubuntu-26.04-LTS-Configuration-Toolkit
cp config/defaults.conf.example config/defaults.conf
sudo vi config/defaults.conf
sudo ./main.sh
```

Update
```bash
git pull origin main
```

---

## Flags

```
Inspection / preview:
  --list                Print discovered modules with metadata and exit.
  --plan                Read-only audit: modules report what they would change.
  --dry-run             Run scripts with bash -n (syntax check, no execution).

Execution control:
  --resume              Skip modules already recorded as complete.
  --force               Re-run all modules, even completed ones.
  --ignore-errors       Continue when a non-critical module exits non-zero.
  --test                Run end-to-end idempotency validation (CI/CD mode).
  -h, --help            Show this help and exit.
  -v, --version         Show version and exit.
```

### Flag conflict resolution

| Combination | Behaviour |
|---|---|
| `--force` + `--resume` | `--force` wins (re-run all) |
| `--plan` + others | `--plan` wins (no changes) |
| `--list` + others | `--list` only (print and exit) |

---

## Configuration

All variables live in `config/defaults.conf` (gitignored — copy from
`config/defaults.conf.example`). The most important fields:

| Variable | Description |
|---|---|
| `NETWORK_INTERFACE` | Interface to configure (e.g. `ens3`) |
| `USE_DHCP` | `true` for DHCP, `false` for static IP |
| `IP_ADDRESS`, `PREFIX_LENGTH`, `GATEWAY`, `DNS_SERVERS` | Static IP fields |
| `HOSTNAME` | FQDN for the host |
| `TIMEZONE`, `LOCALE` | Locale settings |
| `NTP_SERVERS`, `FALLBACK_NTP` | chrony servers |
| `EMAIL_TO`, `SMTP_RELAY_HOST`, `SMTP_RELAY_PORT` | Mail relay |
| `DISK_ALERT_THRESHOLD` | Disk-usage % that triggers an alert |

The following values are **never stored in config files** — they are prompted
interactively (or supplied via env var for unattended runs):

| Env var | Used by | Effect |
|---|---|---|
| `ADMIN_USER`, `ADMIN_PASSWORD` | `01-base-config` | Create sudo user without prompting |
| `TOOLKIT_NONINTERACTIVE=1` | All | Use defaults for any interactive prompt |

---

## Unattended mode

```bash
ADMIN_USER=sysadmin \
ADMIN_PASSWORD='change-me-please' \
TOOLKIT_NONINTERACTIVE=1 \
sudo -E ./main.sh
```

Recommended secure pattern (avoids passwords in shell history):

```bash
chmod 600 .env
set -a; source .env; set +a
sudo -E ./main.sh
```

---

## Modules

Modules live in `scripts/` and are auto-discovered alphabetically. Each module
declares its metadata in a header:

```bash
# MODULE:      06-hardening
# SUMMARY:     Kernel sysctl hardening, AppArmor verification, auditd setup
# DEPENDS:     05-packages
# IDEMPOTENT:  yes
# DESTRUCTIVE: no
# ADDED:       1.0.0
```

| # | Script | What it does |
|---|---|---|
| 00 | `00-preflight.sh` | OS=Ubuntu Server 26.04, internet, disk space, apt locks |
| 01 | `01-base-config.sh` | apt upgrade, sudo user, unattended-upgrades |
| 02 | `02-ip-config.sh` | Hostname, Netplan, connectivity check + auto-restore |
| 03 | `03-network-hardening.sh` | cloud-init off, NetworkManager off, UFW (SSH-only), IPv6 off, fail2ban |
| 04 | `04-system-settings.sh` | Timezone, locale, chrony (replaces systemd-timesyncd) |
| 05 | `05-packages.sh` | Standard editor / monitoring / network tools |
| 06 | `06-hardening.sh` | sysctl, AppArmor verify, auditd rules |
| 07 | `07-monitoring.sh` | sysstat, rsyslog rules, logrotate |
| 08 | `08-mail-alerting.sh` | Postfix relay, daily report cron, disk/service alert cron |
| 99 | `99-cleanup.sh` | apt autoremove + clean, service verification, banner |

### Adding your own module

Drop `scripts/50-mycompany.sh` with a metadata header — it is picked up
automatically. See `CONTRIBUTING.md` for naming conventions and how to register
dependencies.

### Hooks

Optional `scripts/hooks/pre-<module>.sh` and `scripts/hooks/post-<module>.sh`
files run before/after the matching module. Hook failures are logged but never
stop the run.

---

## State and logging

The toolkit writes a state file recording which modules completed:

| State file | Survives reboot? |
|---|---|
| `/var/log/toolkit-setup/.state` | yes |

Log file:

| Log file |
|---|
| `/var/log/toolkit-setup/toolkit-setup.log` |

After a failed run, use `sudo ./main.sh --resume` to pick up where you left off,
or `sudo ./main.sh --force` to re-run everything from scratch.

---

## Troubleshooting / quick recovery

| Symptom | Fix |
|---|---|
| Network broken after `02-ip-config` | `cp -a /etc/netplan.backup/. /etc/netplan/ && netplan apply` |
| One module failed | `sudo ./main.sh --resume` (continue from where it failed) |
| Need to re-run from scratch | `sudo ./main.sh --force` |
| `--list` shows wrong dependency | Inspect the `# DEPENDS:` header in the module |

Inspect the log for ERROR lines:
```bash
grep ERROR /var/log/toolkit-setup/toolkit-setup.log
```

---

## Development Setup (for contributors)

If you're contributing code changes, set up development hooks:

```bash
bash scripts/setup-hooks.sh
```

This enables automatic checks for:
- ✅ VERSION file updates on code changes
- ✅ Semantic versioning validation
- ✅ CHANGELOG.md updates

**When making a PR**, update VERSION and CHANGELOG.md with your changes:
```bash
# See current version
cat VERSION

# Update VERSION based on your changes (MAJOR.MINOR.PATCH)
echo "1.1.0" > VERSION

# Update CHANGELOG.md under Releases section
vi CHANGELOG.md

# Commit (hooks will validate)
git commit -am "Your changes"
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file 
for the full text.

### Copyright

© 2026 WildcatKSS

### MIT License Summary

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software to use, modify, merge, publish, distribute, sublicense, and/or
sell copies, subject only to the following conditions:

- The above copyright notice and this permission notice must be included in all
  copies or substantial portions of the software.
- The software is provided "as-is" without any warranty or liability.

For full terms, see [LICENSE](LICENSE).
