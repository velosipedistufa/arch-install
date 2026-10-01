#!/bin/sh
# Any backlight brightnessctl finds. No-op when the machine has none,
# so the same waybar config is fine on a desktop and a laptop.
set -eu
if ! ls /sys/class/backlight/*/brightness >/dev/null 2>&1; then
	exit 0
fi
command -v brightnessctl >/dev/null 2>&1 || exit 0

refresh() {
	pkill -RTMIN+8 waybar 2>/dev/null || true
}

case "${1:-}" in
	up)
		brightnessctl -c backlight -q set +5%
		refresh
		;;
	down)
		brightnessctl -c backlight -q set 5%-
		refresh
		;;
	status)
		line=$(brightnessctl -c backlight -m 2>/dev/null | head -n 1 || true)
		[ -n "$line" ] || exit 0
		pct=${line##*,}
		pct=${pct%\%}
		if [ "$pct" -ge 66 ]; then
			icon='󰃠'
		elif [ "$pct" -ge 33 ]; then
			icon='󰃟'
		else
			icon='󰃞'
		fi
		printf '{"text":"%s","tooltip":"Brightness %s%%","percentage":%s}\n' "$icon" "$pct" "$pct"
		;;
	*)
		exit 1
		;;
esac
