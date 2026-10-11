#!/bin/bash
# QEMU-only hook. The host test mounts the repo and the package cache, then runs this.
set -euo pipefail

vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
[[ $vendor == QEMU ]] || {
	echo "guest-phase1.sh is the QEMU test hook, not the installer." >&2
	exit 1
}
[[ -d /mnt/repo && -d /mnt/pkgcache ]] || {
	echo "Mount the repo and pkgcache 9p shares on /mnt/repo and /mnt/pkgcache first." >&2
	exit 1
}

bytes=$(lsblk -bno SIZE /dev/vda | head -1)
[[ ${bytes:-0} -gt 20000000000 ]] || {
	echo "Refusing to install: /dev/vda is ${bytes:-missing} bytes." >&2
	lsblk >&2 || true
	exit 1
}

rm -rf /root/arch-install
mkdir -p /root/arch-install
tar -C /mnt/repo \
	--exclude=./secrets.sh \
	--exclude=./globals.sh \
	--exclude=./VM \
	--exclude=./.git \
	--exclude=__pycache__ \
	-cf - . | tar -C /root/arch-install -xf -

cat >/root/arch-install/secrets.sh <<'EOF'
USER_NAME=qa
USER_PASSWORD=1234
HOSTNAME=archvm
LOCALE=en_US.UTF-8
TIMEZONE=UTC
DISK=/dev/vda
HOME_SERVER_IID=6
HOME_SERVER_LABEL=::6
HOME_SERVER=
LAN_BCAST=
VPS_HOST=
VPS_A=
VPS_AAAA=
VPS_LABEL=VPS
KEYBOARD_EVENT=
KEYBOARD_UNIQ=
SCREENSHOT_LOCAL_DIR=/tmp/screenshots
SCREENSHOT_DAV_URL=
SCREENSHOT_DAV_USER=
SCREENSHOT_DAV_PASSWORD=
EOF
chmod 600 /root/arch-install/secrets.sh

for _ in $(seq 1 40); do
	ip -4 -o addr show scope global | grep -q . && break
	sleep 1
done

export PACMAN_CACHE=/mnt/pkgcache
export ARCH_INSTALL_YES=1
export ARCH_INSTALL_SERIAL=1
if ! bash /root/arch-install/install-base.sh; then
	echo INSTALL_BASE_FAIL
	poweroff || true
	exit 1
fi
echo PHASE1_DONE
poweroff
