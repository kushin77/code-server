#!/usr/bin/env bash
################################################################################
# File:          scripts/lib/vpn.sh
# Owner:         Platform Engineering
# Purpose:       Reusable VPN validation helpers for endpoint scan/test scripts.
# Usage:         source "scripts/lib/vpn.sh"
# Last Updated:  April 15, 2026
################################################################################

set -euo pipefail

vpn::require_commands() {
	local missing=0
	for cmd in ip getent; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			echo "[vpn] missing required command: $cmd" >&2
			missing=1
		fi
	done
	if [[ "$missing" -ne 0 ]]; then
		return 1
	fi
}

vpn::require_interface() {
	local iface=${1:-wg0}
	if ! ip link show "$iface" >/dev/null 2>&1; then
		echo "[vpn] required interface not found: $iface" >&2
		return 1
	fi
}

vpn::resolve_first_ip() {
	local host=$1
	getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}'
}

vpn::route_line_for_host() {
	local host=$1
	ip route get "$host" 2>/dev/null | head -1
}

vpn::route_uses_interface() {
	local host=$1
	local iface=${2:-wg0}
	local route_line
	route_line=$(vpn::route_line_for_host "$host" || true)
	[[ "$route_line" == *" dev $iface "* ]]
}

vpn::assert_route_uses_interface() {
	local host=$1
	local iface=${2:-wg0}
	local route_line
	route_line=$(vpn::route_line_for_host "$host" || true)

	if [[ -z "$route_line" ]]; then
		echo "[vpn] no route found for host: $host" >&2
		return 1
	fi

	if [[ "$route_line" != *" dev $iface "* ]]; then
		echo "[vpn] host '$host' does not route through $iface" >&2
		echo "[vpn] actual route: $route_line" >&2
		return 1
	fi
}

vpn::assert_hosts_route_via_interface() {
	local iface=${1:-wg0}
	shift
	local host

	for host in "$@"; do
		vpn::assert_route_uses_interface "$host" "$iface"
	done
}
