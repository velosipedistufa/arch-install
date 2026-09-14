#!/bin/sh
# Region screenshot: grim + slurp → clipboard, local dir, Nextcloud WebDAV (domain, not LAN IP).
set -eu

G="${HOME}/.config/arch-install/globals.sh"
[ -f "$G" ] || G="${HOME}/.config/setup_linux/globals.sh"
[ -f "$G" ] && . "$G"

LOCAL_DIR="${SCREENSHOT_LOCAL_DIR:-/tmp/screenshots}"
mkdir -p "$LOCAL_DIR"
file="$LOCAL_DIR/$(date +%Y%m%d_%H%M%S)_grim.png"

geom=$(slurp) || exit 0
grim -g "$geom" "$file"
wl-copy -t image/png < "$file"

notify() {
	command -v notify-send >/dev/null 2>&1 || return 0
	notify-send -a screenshot "$1" "$2" || true
}

if [ -z "${SCREENSHOT_DAV_URL:-}" ] || [ -z "${SCREENSHOT_DAV_USER:-}" ]; then
	notify "Screenshot" "saved $file (no WebDAV in globals.sh)"
	exit 0
fi

base="${SCREENSHOT_DAV_URL%/}"
name=$(basename "$file")
if curl -sS -f -m 60 -u "${SCREENSHOT_DAV_USER}:${SCREENSHOT_DAV_PASSWORD}" \
	-T "$file" "$base/$name" >/dev/null; then
	notify "Screenshot" "clipboard + $LOCAL_DIR + Nextcloud"
else
	notify "Screenshot" "clipboard + $file (Nextcloud upload failed)"
	exit 1
fi
