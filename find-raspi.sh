#!/usr/bin/env bash

set -euo pipefail

DEFAULT_SSH_USER="${SSH_USER:-pi}"
DEFAULT_TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1}"

print_usage() {
	cat <<'EOF'
Usage:
  ./find-raspi.sh [subnet_prefix] [ssh_user]

Examples:
  ./find-raspi.sh
  ./find-raspi.sh 192.168.8
  ./find-raspi.sh 192.168.178 pi

Environment variables:
  SSH_USER         Default SSH user (default: pi)
  TIMEOUT_SECONDS  Ping/port timeout in seconds (default: 1)

The script scans x.x.x.1 - x.x.x.254, pings reachable hosts and checks
whether TCP port 22 is open. Matching hosts are printed with a ready-to-use
SSH command.
EOF
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

detect_subnet_prefix() {
	local ipv4

	if command_exists ip; then
		ipv4="$(ip -4 addr show scope global | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
	elif command_exists hostname; then
		ipv4="$(hostname -I 2>/dev/null | awk '{print $1}')"
	else
		ipv4=""
	fi

	if [[ -z "$ipv4" ]]; then
		echo "Konnte kein lokales IPv4-Netz automatisch erkennen." >&2
		echo "Bitte Subnetz explizit angeben, z. B.: ./find-raspi.sh 192.168.178" >&2
		exit 1
	fi

	awk -F. 'NF == 4 { printf "%s.%s.%s", $1, $2, $3 }' <<<"$ipv4"
}

can_ping() {
	local target_ip="$1"

	if ping -c 1 -W "$DEFAULT_TIMEOUT_SECONDS" "$target_ip" >/dev/null 2>&1; then
		return 0
	fi

	return 1
}

has_ssh_port() {
	local target_ip="$1"

	if command_exists nc; then
		nc -z -w "$DEFAULT_TIMEOUT_SECONDS" "$target_ip" 22 >/dev/null 2>&1
		return $?
	fi

	if command_exists timeout; then
		timeout "$DEFAULT_TIMEOUT_SECONDS" bash -c "</dev/tcp/${target_ip}/22" >/dev/null 2>&1
		return $?
	fi

	bash -c "</dev/tcp/${target_ip}/22" >/dev/null 2>&1
}

main() {
	local subnet_prefix="${1:-}"
	local ssh_user="${2:-$DEFAULT_SSH_USER}"
	local found_any=0
	local ip_suffix
	local ip_address

	case "${subnet_prefix:-}" in
		-h|--help|help)
			print_usage
			exit 0
			;;
	esac

	if [[ -z "$subnet_prefix" ]]; then
		subnet_prefix="$(detect_subnet_prefix)"
	fi

	echo "Scanne ${subnet_prefix}.1-254 auf erreichbare Hosts mit offenem SSH-Port 22 ..."
	echo

	for ip_suffix in $(seq 1 254); do
		ip_address="${subnet_prefix}.${ip_suffix}"

		if ! can_ping "$ip_address"; then
			continue
		fi

		if has_ssh_port "$ip_address"; then
			printf 'SSH erreichbar: %-15s  Befehl: ssh %s@%s\n' "$ip_address" "$ssh_user" "$ip_address"
			found_any=1
		else
			printf 'Host online:    %-15s  SSH-Port 22 geschlossen\n' "$ip_address"
		fi
		done

	if [[ "$found_any" -eq 0 ]]; then
		echo "Kein Host mit offenem SSH-Port gefunden."
		echo "Tipp: Subnetz explizit angeben, z. B. ./find-raspi.sh 192.168.178"
		return 1
	fi

	return 0
}

main "$@"
