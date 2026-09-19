#!/bin/sh
# Lock keeps this logind session. Exit to ly ends it (next login is a new session).
set -eu

choice=$(printf '%s\n' Cancel Lock Suspend 'Exit to ly' | fuzzel --dmenu --prompt 'session> ' --width 24 --lines 4 || true)
case "${choice:-}" in
	Lock)
		exec swaylock -f
		;;
	Suspend)
		# Lock first so resume is the same session, not a black screen.
		swaylock -f
		exec systemctl suspend
		;;
	'Exit to ly')
		# Kill dwl only. start-dwl.sh is waiting on it and will return to ly.
		# terminate-session + lingering user manager leaves stale wayland sockets
		# (no waybar/wallpaper on the next login).
		pkill -x dwl
		exit 0
		;;
	*)
		exit 0
		;;
esac
