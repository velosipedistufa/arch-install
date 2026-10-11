# Shared helpers for the install scripts. Source this file; do not execute it.
# Secrets are loaded only from the path passed in, or from ./secrets.sh.
# Runtime programs (waybar, start-dwl) use the copy under ~/.config instead.

die() {
	printf '%s\n' "$*" >&2
	exit 1
}

log() {
	printf '==> %s\n' "$*"
}

need_root() {
	[[ "$(id -u)" -eq 0 ]] || die "Run this as root."
}

repo_root() {
	local src
	src=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
	printf '%s\n' "$src"
}

load_secrets() {
	local root file
	root=$(repo_root)
	file=${ARCH_INSTALL_SECRETS:-$root/secrets.sh}
	[[ -f $file ]] || die "Missing $file
Copy secrets.example.sh to secrets.sh and edit it.
secrets.sh is gitignored. Do not commit it."
	# shellcheck disable=SC1090
	. "$file"
	SECRETS_FILE=$file
}

require_var() {
	local name=$1
	[[ -n ${!name:-} ]] || die "Set $name in $SECRETS_FILE"
}

read_packages() {
	local file=$1 line
	[[ -f $file ]] || die "Missing package list: $file"
	while IFS= read -r line || [[ -n $line ]]; do
		line=${line%%#*}
		# shellcheck disable=SC2086
		line=${line//[[:space:]]/}
		[[ -n $line ]] || continue
		printf '%s\n' "$line"
	done <"$file"
}

pkg_cache_dir() {
	if [[ -n ${PACMAN_CACHE:-} && -d $PACMAN_CACHE ]]; then
		printf '%s\n' "$PACMAN_CACHE"
	elif [[ -d /mnt/gentoo/arch-pkg-cache ]]; then
		printf '%s\n' /mnt/gentoo/arch-pkg-cache
	fi
}

# Copy the running pacman.conf and, when a local cache exists, search it
# after the normal cache. Downloads still go to the first (writable) directory.
write_pacman_conf() {
	local dest=$1 cache=$2
	awk -v cache="$cache" '
		/^[[:space:]]*CacheDir[[:space:]]*=/ { next }
		/^\[options\][[:space:]]*$/ {
			print
			if (cache != "") {
				print "CacheDir = /var/cache/pacman/pkg"
				print "CacheDir = " cache
			}
			next
		}
		{ print }
	' /etc/pacman.conf >"$dest"
}

disk_part() {
	local disk=$1 n=$2
	case "$(basename "$disk")" in
	nvme*n[0-9] | mmcblk* | loop* | nbd*)
		printf '%sp%s\n' "$disk" "$n"
		;;
	*)
		if [[ $disk == *by-id* || $disk == *by-path* ]]; then
			printf '%s-part%s\n' "$disk" "$n"
		else
			printf '%s%s\n' "$disk" "$n"
		fi
		;;
	esac
}

disk_is_busy() {
	local disk=$1 mp
	while read -r mp; do
		[[ -n $mp ]] && return 0
	done < <(lsblk -nr -o MOUNTPOINT "$disk")
	return 1
}

confirm_disk() {
	local answer parent
	[[ -n ${DISK:-} ]] || die "Set DISK in $SECRETS_FILE"
	[[ $DISK == /dev/* ]] || die "DISK must be a /dev path, not a partition nickname."
	[[ -b $DISK ]] || die "$DISK is not a block device."
	parent=$(lsblk -no PKNAME "$DISK" 2>/dev/null || true)
	[[ -z $parent ]] || die "$DISK is a partition. Set DISK to the whole disk (for example /dev/nvme0n1 or /dev/vda)."
	if disk_is_busy "$DISK"; then
		lsblk -o NAME,SIZE,TYPE,MOUNTPOINT "$DISK" >&2 || true
		die "Refusing to wipe $DISK because a filesystem on it is mounted."
	fi
	log "This will erase $DISK"
	lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL "$DISK" || true
	if [[ ${ARCH_INSTALL_YES:-} == 1 ]]; then
		log "ARCH_INSTALL_YES=1, continuing without a prompt."
		return 0
	fi
	[[ -t 0 ]] || die "Refusing to wipe $DISK without a terminal. Type the disk path when asked, or set ARCH_INSTALL_YES=1."
	printf 'Type %s to erase it: ' "$DISK"
	read -r answer
	[[ $answer == "$DISK" ]] || die "Aborted. Nothing was written."
}

as_user() {
	local uid
	uid=$(id -u "$USER_NAME")
	runuser -u "$USER_NAME" -- env \
		HOME="/home/${USER_NAME}" \
		XDG_RUNTIME_DIR="/run/user/${uid}" \
		DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
		"$@"
}
