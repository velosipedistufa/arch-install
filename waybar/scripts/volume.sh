#!/bin/sh
# Sink volume: 0–5 in 1% steps, 5–100 in 5% steps.
# 0→1→2→3→4→5→10→…→100 and the reverse.
set -eu
SINK="@DEFAULT_AUDIO_SINK@"

vol_now() {
	# "Volume: 0.45" or "Volume: 0.45 [MUTED]"
	wpctl get-volume "$SINK" | awk '{
		v=$2
		printf "%d", int(v * 100 + 0.5)
	}'
}

dir="${1:-}"
cur=$(vol_now)
case "$dir" in
	up)
		if [ "$cur" -lt 5 ]; then
			next=$((cur + 1))
		elif [ $((cur % 5)) -eq 0 ]; then
			next=$((cur + 5))
		else
			next=$(((cur / 5 + 1) * 5))
		fi
		[ "$next" -gt 100 ] && next=100
		;;
	down)
		if [ "$cur" -gt 5 ]; then
			if [ $((cur % 5)) -eq 0 ]; then
				next=$((cur - 5))
			else
				next=$((cur / 5 * 5))
				[ "$next" -lt 5 ] && next=5
			fi
		elif [ "$cur" -gt 0 ]; then
			next=$((cur - 1))
		else
			next=0
		fi
		;;
	*)
		echo "Usage: $0 up|down" >&2
		exit 1
		;;
esac

wpctl set-volume -l 1.0 "$SINK" "${next}%"
