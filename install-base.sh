#!/bin/bash
# Stage 1, run from the Arch live ISO (or a UEFI virtual machine).
# Partition the disk, install a bootable console system, and stop.
# This script does not reboot.
set -euo pipefail
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

need_root
load_secrets
require_var USER_NAME
require_var USER_PASSWORD
require_var HOSTNAME
require_var DISK

[[ $USER_NAME != youruser ]] || die "Edit USER_NAME in $SECRETS_FILE (it is still the example value)."
[[ $USER_PASSWORD != changeme ]] || die "Edit USER_PASSWORD in $SECRETS_FILE (it is still the example value)."
[[ $USER_PASSWORD != *$'\n'* ]] || die "USER_PASSWORD must be a single line."
[[ $USER_NAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "USER_NAME must be a lowercase Linux user name."
[[ $HOSTNAME =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || die "HOSTNAME is not a single DNS label."
[[ -d /sys/firmware/efi ]] || die "UEFI was not detected. Boot the install medium in UEFI mode."

for cmd in sgdisk partprobe mkfs.fat mkfs.ext4 pacstrap genfstab arch-chroot; do
	command -v "$cmd" >/dev/null 2>&1 || die "Missing $cmd. Run install-base.sh from the Arch live ISO."
done

if command -v loadkeys >/dev/null 2>&1; then
	loadkeys colemak || log "Could not switch this console to colemak. The installed system still gets the keymap."
fi

confirm_disk

locale=${LOCALE:-en_US.UTF-8}
timezone=${TIMEZONE:-UTC}
[[ $locale =~ ^[A-Za-z0-9_.@-]+$ ]] || die "LOCALE looks unsafe: $locale"
[[ $timezone =~ ^[A-Za-z0-9_/+-]+$ ]] || die "TIMEZONE looks unsafe: $timezone"

mapfile -t base_pkgs < <(read_packages "$HERE/packages/base.txt")
ucode=()
if grep -q GenuineIntel /proc/cpuinfo; then
	ucode=(intel-ucode)
elif grep -q AuthenticAMD /proc/cpuinfo; then
	ucode=(amd-ucode)
fi

log "Partitioning $DISK"
sgdisk --zap-all "$DISK"
sgdisk \
	-n 1:0:+1G -t 1:ef00 -c 1:"EFI System" \
	-n 2:0:0 -t 2:8300 -c 2:"Linux root" \
	"$DISK"
partprobe "$DISK" || true
udevadm settle || true

efi=$(disk_part "$DISK" 1)
root=$(disk_part "$DISK" 2)
for _ in $(seq 1 50); do
	[[ -b $efi && -b $root ]] && break
	sleep 0.1
done
[[ -b $efi && -b $root ]] || die "Partitions did not appear ($efi, $root)."

if findmnt -rno TARGET /mnt >/dev/null 2>&1; then
	die "/mnt is already mounted. Unmount it before installing."
fi

log "Formatting $root and $efi"
wipefs -a "$root" "$efi" >/dev/null
mkfs.ext4 -F "$root"
mkfs.fat -F 32 "$efi"
# Probe order on the live ISO can miss a just-written FAT and try squashfs.
mount -t ext4 "$root" /mnt
cleanup_mount() {
	if findmnt -rno TARGET /mnt >/dev/null 2>&1; then
		umount -R /mnt || log "Left /mnt mounted. Before you power off: umount -R /mnt"
	fi
}
trap cleanup_mount EXIT
mount -t vfat --mkdir "$efi" /mnt/boot

# The live ISO already has a keyring. --init rewrites it and fails when the
# RNG is empty. --populate only refreshes local signatures on the master keys.
log "Preparing the keyring"
if ! pacman-key --list-keys >/dev/null 2>&1; then
	pacman-key --init
fi
pacman-key --populate archlinux || log "pacman-key --populate reported errors. Continuing with the keyring package."

cache=$(pkg_cache_dir)
conf=$(mktemp)
write_pacman_conf "$conf" "$cache"
if [[ -n $cache ]]; then
	log "Using package cache $cache"
fi
if ! pacman --config "$conf" -Sy --noconfirm archlinux-keyring; then
	# An older ISO does not trust the packager key on the current keyring package.
	keyring=""
	if [[ -n $cache ]]; then
		keyring=$(find "$cache" -name 'archlinux-keyring-*.pkg.tar.zst' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
	fi
	[[ -n $keyring && -f $keyring ]] || die "Could not install archlinux-keyring. Put that package in PACMAN_CACHE or use a newer ISO."
	log "Installing $keyring without a signature check, then verifying every other package."
	unsigned=$(mktemp)
	awk '
		/^[[:space:]]*SigLevel[[:space:]]*=/ { print "SigLevel = Never"; next }
		{ print }
	' "$conf" >"$unsigned"
	pacman --config "$unsigned" -U --noconfirm "$keyring"
	rm -f "$unsigned"
fi

log "Installing the base system"
# Copy the live keyring into the new system. -K would build a new one and
# needs a working RNG, which a VM does not have unless virtio-rng is attached.
pacstrap -C "$conf" /mnt "${base_pkgs[@]}" "${ucode[@]}"
rm -f "$conf"
genfstab -U /mnt >>/mnt/etc/fstab

install -m 600 "$SECRETS_FILE" /mnt/root/secrets.install
{
	printf 'ARCH_INSTALL_SERIAL=%q\n' "${ARCH_INSTALL_SERIAL:-}"
	printf 'LOCALE=%q\n' "$locale"
	printf 'TIMEZONE=%q\n' "$timezone"
} >/mnt/root/install.env
chmod 600 /mnt/root/install.env

cat >/mnt/root/install-chroot.sh <<'EOF'
#!/bin/bash
set -euo pipefail
trap 'rm -f /root/secrets.install /root/install.env /root/install-chroot.sh' EXIT
# shellcheck disable=SC1091
. /root/secrets.install
# shellcheck disable=SC1091
. /root/install.env

timedatectl set-ntp true || true

if [[ ! -f /swapfile ]]; then
	mkswap -U clear --size 4G --file /swapfile
fi
swapon /swapfile || true
grep -q '[[:space:]]/swapfile[[:space:]]' /etc/fstab || printf '%s\n' '/swapfile none swap defaults 0 0' >>/etc/fstab

printf '%s\n' "$HOSTNAME" >/etc/hostname
cat >/etc/hosts <<HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}
HOSTS

sed -i "s/^#[[:space:]]*\\(${LOCALE} UTF-8\\)/\\1/" /etc/locale.gen
printf 'LANG=%s\n' "$LOCALE" >/etc/locale.conf
locale-gen

printf 'KEYMAP=colemak\n' >/etc/vconsole.conf
if [[ -n ${TIMEZONE:-} && -e /usr/share/zoneinfo/${TIMEZONE} ]]; then
	ln -sfn "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
fi
hwclock --systohc || true

if ! id -u "$USER_NAME" >/dev/null 2>&1; then
	useradd -m -G wheel -s /usr/bin/zsh "$USER_NAME"
fi
printf '%s:%s\n' "$USER_NAME" "$USER_PASSWORD" | chpasswd --crypt-method YESCRYPT

install -Dm440 /dev/stdin /etc/sudoers.d/10-wheel <<'SUDO'
%wheel ALL=(ALL:ALL) ALL
SUDO
visudo -cf /etc/sudoers.d/10-wheel

if [[ ${ARCH_INSTALL_SERIAL:-} == 1 ]]; then
	# Serial console is for the QEMU test. A normal install leaves GRUB's default cmdline.
	sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 console=tty0 console=ttyS0,115200"/' /etc/default/grub
	systemctl enable serial-getty@ttyS0.service
fi
if grep -q '^#\?GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
	sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
else
	printf '%s\n' 'GRUB_DISABLE_OS_PROBER=false' >>/etc/default/grub
fi

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg
mkinitcpio -P
systemctl enable NetworkManager.service
EOF
chmod 700 /mnt/root/install-chroot.sh

log "Configuring the new system"
arch-chroot /mnt /root/install-chroot.sh

dest="/mnt/home/${USER_NAME}/GitRepos/arch-install"
log "Copying this checkout to /home/${USER_NAME}/GitRepos/arch-install on the new system"
install -d "$dest"
tar -C "$HERE" \
	--exclude=./VM \
	--exclude=./waybar/hw.json \
	--exclude=__pycache__ \
	--exclude='*.pyc' \
	-cf - . | tar -C "$dest" -xf -
chmod 600 "$dest/secrets.sh"
# qa exists in the new /etc/passwd, not on the live ISO.
arch-chroot /mnt chown -R "${USER_NAME}:${USER_NAME}" "/home/${USER_NAME}"

sync
trap - EXIT
if ! umount -R /mnt; then
	log "Detach busy mounts under /mnt."
	umount -l /mnt || log "Could not unmount /mnt. Before you power off: umount -R /mnt"
fi

cat <<EOF

INSTALL_BASE_OK

The base system is installed on ${DISK}. Nothing has been rebooted.

Colemak is saved in the new system's /etc/vconsole.conf.
After you boot that disk, the console keymap is colemak.
Log in as ${USER_NAME}. Type the password with colemak, the same way you typed it into secrets.sh.

Do this yourself:
  1. Power off. Eject the USB stick or unmount the ISO.
  2. In the firmware boot menu, boot the disk you just installed (${DISK}), not the install medium.
  3. Log in on the console. Connect the network if it is not already up
     (ethernet uses NetworkManager; for wifi: nmtui).
  4. Finish the desktop:
       cd ~/GitRepos/arch-install
       sudo ./install-desktop.sh
EOF
