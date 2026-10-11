#!/bin/bash
# QEMU-only hook, run on the installed system as the test user.
set -euo pipefail

vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
[[ $vendor == QEMU ]] || {
	echo "guest-phase2.sh is the QEMU test hook, not the installer." >&2
	exit 1
}

repo=${HOME}/GitRepos/arch-install
# shellcheck disable=SC1091
. "$repo/secrets.sh"

# Refresh scripts from the host checkout without touching the VM's secrets.sh.
if [[ -d /mnt/repo/install-desktop.sh || -f /mnt/repo/install-desktop.sh ]]; then
	tar -C /mnt/repo \
		--exclude=./secrets.sh \
		--exclude=./globals.sh \
		--exclude=./.git \
		--exclude=__pycache__ \
		-cf - . | tar -C "$repo" -xf -
fi

sudo_as() {
	printf '%s\n' "$USER_PASSWORD" | sudo -S -p '' "$@"
}

echo "COLEMAK_CONF=$(grep '^KEYMAP=' /etc/vconsole.conf || true)"
echo "COLEMAK_KC18=$(sudo_as dumpkeys | awk '/keycode *18 /{print; exit}')"

sudo_as mkdir -p /mnt/pkgcache
if ! mountpoint -q /mnt/pkgcache; then
	sudo_as mount -t 9p -o trans=virtio,version=9p2000.L,msize=104857600,ro pkgcache /mnt/pkgcache
fi

for _ in $(seq 1 60); do
	ip -4 -o addr show scope global | grep -q . && break
	sleep 1
done

export PACMAN_CACHE=/mnt/pkgcache
cd "$repo"
if ! printf '%s\n' "$USER_PASSWORD" | sudo -S -p '' --preserve-env=PACMAN_CACHE ./install-desktop.sh; then
	echo INSTALL_DESKTOP_FAIL
	exit 1
fi
echo PHASE2_DONE
