#!/bin/sh
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=dwl
export XDG_SESSION_DESKTOP=dwl
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# wlroots treats WAYLAND_DISPLAY as "nest on that compositor".
unset WAYLAND_DISPLAY
unset DISPLAY

export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland
export QT_QPA_PLATFORM=wayland
export CLUTTER_BACKEND=wayland
export SDL_VIDEODRIVER=wayland
export ELECTRON_OZONE_PLATFORM_HINT=wayland
export _JAVA_AWT_WM_NONREPARENTING=1

G="${HOME}/.config/arch-install/globals.sh"
[ -f "$G" ] || G="${HOME}/.config/setup_linux/globals.sh"
[ -f "$G" ] && . "$G"

LOG="${HOME}/.cache/dwl-start.log"
mkdir -p "${HOME}/.cache"
log() { echo "$*" >>"$LOG"; }
log "----- $(date) pid=$$ runtime=$XDG_RUNTIME_DIR -----"

# Linger keeps /run/user/$UID across ly logout. Stale wayland-* makes
# waybar/swaybg start against a dead display, then the new dwl comes up alone.
if ! pgrep -x dwl >/dev/null 2>&1; then
	rm -f "${XDG_RUNTIME_DIR}/wayland-"* "${XDG_RUNTIME_DIR}/wayland-"*.lock
	log "cleared stale compositor sockets"
fi

DW="${HOME}/appearance/dwl/dwl"
[ -x "$DW" ] || DW=dwl
"$DW" >/dev/null 2>>"$LOG" &
DWL_PID=$!
log "dwl pid $DWL_PID"

SOCK="${XDG_RUNTIME_DIR}/wayland-0"
ok=0
i=0
while [ "$i" -lt 80 ]; do
	if [ -S "$SOCK" ] && kill -0 "$DWL_PID" 2>/dev/null; then
		# socket must belong to this dwl, not a leftover
		ok=1
		break
	fi
	i=$((i + 1))
	sleep 0.1
done

if [ "$ok" -ne 1 ]; then
	log "dwl did not create $SOCK"
	wait "$DWL_PID" || true
	exit 1
fi

export WAYLAND_DISPLAY=wayland-0
log "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"

/usr/lib/xdg-desktop-portal-wlr &
pgrep -x mako >/dev/null 2>&1 || mako >>"$LOG" 2>&1 &
if [ -n "${KEYBOARD_EVENT:-}" ] && [ -r "${KEYBOARD_EVENT}" ]; then
	pgrep -x layout-watch >/dev/null 2>&1 || "$HOME/.config/waybar/scripts/layout-watch" "$KEYBOARD_EVENT" >>"$LOG" 2>&1 &
fi

# waybar/swaybg can lose the race; retry a few times
n=0
while [ "$n" -lt 6 ]; do
	pgrep -x waybar >/dev/null 2>&1 || waybar >>"$LOG" 2>&1 &
	pgrep -x swaybg >/dev/null 2>&1 || swaybg -i "$HOME/appearance/wallpaper.png" -m fit -o* >>"$LOG" 2>&1 &
	sleep 0.35
	if pgrep -x waybar >/dev/null 2>&1 && pgrep -x swaybg >/dev/null 2>&1; then
		log "waybar+swaybg up"
		break
	fi
	n=$((n + 1))
	log "retry helpers n=$n"
done

udiskie -A -n >>"$LOG" 2>&1 &
if [ -f "$HOME/.config/swayidle/config" ]; then
	pgrep -x swayidle >/dev/null 2>&1 || swayidle -C "$HOME/.config/swayidle/config" >>"$LOG" 2>&1 &
fi

# User manager lingers across ly logout, so mihomo may still be the pre-setcap
# process. Re-exec on each graphical login so TUN caps and --apply take effect.
if command -v systemctl >/dev/null 2>&1; then
	systemctl --user restart mihomo.service >>"$LOG" 2>&1 || log "mihomo restart failed"
fi

wait "$DWL_PID"
log "dwl exited $?"
