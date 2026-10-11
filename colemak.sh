#!/bin/bash
# Switch the Linux console from qwerty to colemak.
# Works on the Arch live ISO and on an installed system. Does not read secrets.
# The dwl session uses its own keymap (us colemak + ru) from dwl/config.h.
set -euo pipefail

if ! command -v loadkeys >/dev/null 2>&1; then
	echo "colemak.sh: loadkeys is missing. Install the kbd package." >&2
	exit 1
fi

if ! loadkeys colemak; then
	echo "colemak.sh: could not load the colemak keymap." >&2
	exit 1
fi

echo "This console is now colemak."

if [[ -d /run/archiso ]]; then
	echo "Live ISO: the keymap lasts until this medium is shut down."
	echo "install-base.sh writes KEYMAP=colemak into the installed system."
fi

if [[ "$(id -u)" -ne 0 ]]; then
	echo "Not root, so this does not survive a reboot. Run: sudo ./colemak.sh"
	exit 0
fi

if command -v localectl >/dev/null 2>&1 && localectl set-keymap colemak; then
	echo "Saved the console keymap. The next boot will be colemak."
	exit 0
fi

printf 'KEYMAP=colemak\n' >/etc/vconsole.conf
echo "Wrote /etc/vconsole.conf. The next boot will be colemak."
