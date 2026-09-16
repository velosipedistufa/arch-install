#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$HERE/globals.sh" ]; then
	echo "copy globals.example.sh to globals.sh and edit" >&2
	exit 1
fi
# shellcheck disable=SC1091
. "$HERE/globals.sh"

mkswap -U clear --size 4G --file /swapfile
swapon /swapfile
echo /swapfile none swap defaults 0 0 >> /etc/fstab

 timedatectl set-ntp true
 pacman-key --init
 pacman-key --populate archlinux
 pacman -Sy --noconfirm archlinux-keyring

pacman -S --noconfirm grub efibootmgr os-prober

lsblk
cd
grub-install --target=x86_64-efi \
  --efi-directory=/boot \
  --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "${HOSTNAME:-arch}" > /etc/hostname

id -u "$USER_NAME" >/dev/null 2>&1 || useradd -m -G wheel -s /usr/bin/zsh "$USER_NAME"

# Set password (strong hash method). Value comes from globals.sh — not committed.
echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd --crypt-method YESCRYPT

# Enable wheel sudo via drop-in
install -Dm440 /dev/stdin /etc/sudoers.d/10-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

# Validate sudoers syntax
visudo -cf /etc/sudoers.d/10-wheel #
sed -i 's/^#\s*\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen #uncomment locale config
echo LANG=en_US.UTF-8 > /etc/locale.conf
locale-gen
echo  KEYMAP=colemak > /etc/vconsole.conf
mkinitcpio -P
systemctl enable NetworkManager
#passwd
