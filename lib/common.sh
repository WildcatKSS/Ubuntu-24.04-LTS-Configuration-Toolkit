#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
#
# lib/common.sh — Single entry point sourcing all helper modules.
#
# Usage from a module:
#   TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "$TOOLKIT_ROOT/lib/common.sh"

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=log.sh
source "$_lib_dir/log.sh"
# shellcheck source=config.sh
source "$_lib_dir/config.sh"
# shellcheck source=system.sh
source "$_lib_dir/system.sh"
# shellcheck source=pkg.sh
source "$_lib_dir/pkg.sh"
# shellcheck source=state.sh
source "$_lib_dir/state.sh"
# shellcheck source=plan.sh
source "$_lib_dir/plan.sh"
# shellcheck source=service.sh
source "$_lib_dir/service.sh"
# shellcheck source=jail.sh
source "$_lib_dir/jail.sh"

unset _lib_dir
