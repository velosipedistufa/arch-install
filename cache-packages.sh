#!/bin/bash
# Download official packages into a local directory so later installs reuse them.
# AUR builds (paru, wlroots, themes) still fetch their own sources. ly is official.
#
#   sudo ./cache-packages.sh
#   sudo PACMAN_CACHE=/mnt/gentoo/arch-pkg-cache ./cache-packages.sh
set -euo pipefail
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

need_root

cache=${PACMAN_CACHE:-/mnt/gentoo/arch-pkg-cache}
if [[ ! -d $cache ]]; then
	mkdir -p "$cache" || die "Could not create $cache. On a tight root disk, use /mnt/gentoo/arch-pkg-cache."
fi

mapfile -t pkgs < <(read_packages "$HERE/packages/base.txt")
mapfile -t more < <(read_packages "$HERE/packages/desktop.txt")
pkgs+=("${more[@]}" archlinux-keyring intel-ucode amd-ucode)

# An empty local database forces every dependency into the cache. The host's
# installed set would otherwise be treated as already present and skipped.
db=$(mktemp -d)
mkdir -p "$db/sync"
cp -a /var/lib/pacman/sync/. "$db/sync/"
# pacman.conf sets DownloadUser=alpm. That user cannot write a 0700 temp
# database or a cache owned by someone else, so download as root.
conf=$(mktemp)
awk '!/^[[:space:]]*DownloadUser[[:space:]]*=/' /etc/pacman.conf >"$conf"
log "Downloading ${#pkgs[@]} packages and their dependencies into $cache"
pacman --config "$conf" --dbpath "$db" --cachedir "$cache" -Syw --noconfirm "${pkgs[@]}"
rm -rf "$db" "$conf"
log "Package cache is ready: $cache"
log "install-base.sh and install-desktop.sh use this directory when it exists, or when PACMAN_CACHE points at it."
