#!/bin/bash
# Aggregator — sources every lib module in dependency order.
# Back-compat shim for scripts that source shell-utils.sh directly.
#
# Prefer sourcing only what you need:
#     source "$LIB/log.sh"
#     source "$LIB/platform.sh"
#     source "$LIB/nix.sh"

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=log.sh
. "$_LIB_DIR/log.sh"
# shellcheck source=platform.sh
. "$_LIB_DIR/platform.sh"
# shellcheck source=prompt.sh
. "$_LIB_DIR/prompt.sh"
# shellcheck source=packages.sh
. "$_LIB_DIR/packages.sh"
# shellcheck source=misc.sh
. "$_LIB_DIR/misc.sh"
# shellcheck source=nix.sh
. "$_LIB_DIR/nix.sh"
# shellcheck source=docker.sh
. "$_LIB_DIR/docker.sh"
# shellcheck source=bun.sh
. "$_LIB_DIR/bun.sh"
# shellcheck source=audit.sh
. "$_LIB_DIR/audit.sh"
