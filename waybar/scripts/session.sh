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
		exec loginctl terminate-session "${XDG_SESSION_ID:-}"
		;;
	*)
		exit 0
		;;
esac
