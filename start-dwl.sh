#!/bin/sh
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=dwl
export XDG_SESSION_DESKTOP=dwl
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# wlroots treats WAYLAND_DISPLAY as "nest on that compositor".
# If it is set before dwl opens DRM, login fails with
# "couldn't connect to Wayland display" / "failed to create backend".
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

mkdir -p "${HOME}/.cache"
exec >>"${HOME}/.cache/dwl-start.log" 2>&1
echo "----- $(date) pid=$$ runtime=$XDG_RUNTIME_DIR -----"

DW="${HOME}/appearance/dwl/dwl"
[ -x "$DW" ] || DW=dwl
"$DW" &
DWL_PID=$!

for i in $(seq 1 50); do
	[ -S "${XDG_RUNTIME_DIR}/wayland-0" ] && break
	sleep 0.1
done

if [ ! -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
	echo "dwl did not create ${XDG_RUNTIME_DIR}/wayland-0"
	wait "$DWL_PID" || true
	exit 1
fi

export WAYLAND_DISPLAY=wayland-0

/usr/lib/xdg-desktop-portal-wlr &
pgrep -x mako >/dev/null 2>&1 || mako &
if [ -n "${KEYBOARD_EVENT:-}" ] && [ -r "${KEYBOARD_EVENT}" ]; then
	pgrep -x layout-watch >/dev/null 2>&1 || "$HOME/.config/waybar/scripts/layout-watch" "$KEYBOARD_EVENT" &
fi
waybar &
swaybg -i "$HOME/appearance/wallpaper.png" -m fit -o* &
udiskie -A -n &
if [ -f "$HOME/.config/swayidle/config" ]; then
	pgrep -x swayidle >/dev/null 2>&1 || swayidle -C "$HOME/.config/swayidle/config" &
fi

wait "$DWL_PID"
