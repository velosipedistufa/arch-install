#!/usr/bin/env bash
# Toggle mako "do-not-disturb". While on, notifications are not drawn.
set -euo pipefail

has_dnd() {
	makoctl mode 2>/dev/null | grep -qx 'do-not-disturb'
}

case "${1:-toggle}" in
	status)
		if has_dnd; then
			echo dnd
		else
			echo on
		fi
		;;
	on)
		makoctl mode -a do-not-disturb >/dev/null
		makoctl dismiss -a >/dev/null 2>&1 || true
		;;
	off)
		makoctl mode -r do-not-disturb >/dev/null 2>&1 || true
		;;
	toggle)
		if has_dnd; then
			makoctl mode -r do-not-disturb >/dev/null
		else
			makoctl mode -a do-not-disturb >/dev/null
			makoctl dismiss -a >/dev/null 2>&1 || true
		fi
		;;
	*)
		echo "Usage: $0 [toggle|on|off|status]" >&2
		exit 1
		;;
esac
