#!/bin/sh
# Region screenshot: grim + slurp → clipboard, local dir, Nextcloud WebDAV (domain, not LAN IP).
set -eu

# shellcheck disable=SC1090
if [ -n "${ARCH_INSTALL_SECRETS:-}" ] && [ -f "$ARCH_INSTALL_SECRETS" ]; then
	. "$ARCH_INSTALL_SECRETS"
else
	for G in \
		"${HOME}/.config/arch-install/secrets.sh" \
		"${HOME}/.config/arch-install/globals.sh"
	do
		if [ -f "$G" ]; then
			. "$G"
			break
		fi
	done
fi

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
	notify "Screenshot" "saved $file (no WebDAV in secrets.sh)"
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
