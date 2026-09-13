#!/bin/sh
# Laptop backlight only. No-op on a desktop with no /sys/class/backlight.
set -eu
if ! ls /sys/class/backlight/*/brightness >/dev/null 2>&1; then
	exit 0
fi
command -v brightnessctl >/dev/null 2>&1 || exit 0
case "${1:-}" in
	up) brightnessctl -q set +5% ;;
	down) brightnessctl -q set 5%- ;;
	*) exit 1 ;;
esac
