#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$HERE/globals.sh" ]; then
	echo "copy globals.example.sh to globals.sh and edit (user, password, DISK, IPs)" >&2
	exit 1
fi
# shellcheck disable=SC1091
. "$HERE/globals.sh"

HOME_DIR="/home/${USER_NAME}"
REPO="${HERE}"

mkdir -p /usr/share/wayland-sessions
#runuser -u "$USER_NAME" mkdir "$HOME_DIR/appearance/"
#runuser -u "$USER_NAME" scp "${USER_NAME}@${HOME_SERVER}:/home/${USER_NAME}/apearance/archiv.7z" "$HOME_DIR/appearance"
#runuser -u "$USER_NAME" 7z x archiv.7z
sudo cp -a "$REPO/wayland-sessions/." /usr/share/wayland-sessions/
pacman -Syu --noconfirm fuzzel ffmpeg swaybg swayimg waybar pipewire wireplumber wayland libinput pkg-config pipewire-jack git cmatrix btop htop go udiskie xdg-desktop-portal xdg-desktop-portal-wlr kitty yazi transmission mousepad playerctl bluez bluez-utils jq libxss mailcap libxt gnu-free-fonts lxappearance gtk4 pipewire-alsa pipewire-v4l2 sof-firmware alsa-ucm-conf grim slurp wl-clipboard swappy gvfs 7zip neovim hyfetch usbutils wget simple-scan docker blueman bluez bluez-utils android-tools dnsutils llvm gsettings-desktop-schemas udisks2 make python mako noto-fonts-emoji ttf-nerd-fonts-symbols swayidle swaylock brightnessctl waydroid zsh
#pipewire-alsa should be removed as far as firefox will implement pipewire support
cd "$HOME_DIR"
runuser -u "$USER_NAME" git clone https://aur.archlinux.org/paru.git
cd paru
runuser -u "$USER_NAME" makepkg -si
cd ..
runuser -u "$USER_NAME" paru -S --sudoloop wlroots0.19 wayland-protocols ly flat-remix flat-remix-gtk stig mihomo mihomo-tui-git :#vimix-gtk-theme

cd "$REPO"

runuser -u "$USER_NAME" git clone https://codeberg.org/dwl/dwl

cp "$REPO/config.h" "$REPO/dwl"
#ToDo, figure out how to not add dwl to git repo itself, mb gitignore
if [ -f "$REPO/patches/dwl-layout-file.patch" ]; then
	patch -d "$REPO/dwl" -p1 < "$REPO/patches/dwl-layout-file.patch" || true
fi

runuser -u "$USER_NAME"  make
#./dwl
#systemctl enable ly@service #ly@.service outputs Failed to enable unit: Refusing to operate on template unit ly@.service when destination unit multi-user.target is a non-template unit, on both vm and host
systemctl enable ly@tty2.service
systemctl disable getty@tty2.service

runuser -u "$USER_NAME" gsettings set org.gnome.desktop.interface gtk-theme 'Flat-Remix-GTK-Red-Darkest'
runuser -u "$USER_NAME" gsettings set org.gnome.desktop.interface icon-theme 'Flat-Remix-Red-Dark'

systemctl enable --now bluetooth

# waybar: repo is source of truth
install -d "$HOME_DIR/.config/waybar/scripts" "$HOME_DIR/.config/mako" "$HOME_DIR/appearance/waybar" "$HOME_DIR/.config/arch-install" "$HOME_DIR/.cache/waybar"
install -m 600 "$REPO/globals.sh" "$HOME_DIR/.config/arch-install/globals.sh"
chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.config/arch-install/globals.sh"
cp -a "$REPO/waybar/." "$HOME_DIR/.config/waybar/"
cp -a "$REPO/waybar/." "$HOME_DIR/appearance/waybar/"
sudo cp -a "$REPO/waybar/." /etc/xdg/waybar
install -d "$HOME_DIR/.config/swaylock" "$HOME_DIR/.config/swayidle"
install -m 644 "$REPO/waybar/mako/config" "$HOME_DIR/.config/mako/config"
install -m 644 "$REPO/swaylock/config" "$HOME_DIR/.config/swaylock/config"
install -m 644 "$REPO/swayidle/config" "$HOME_DIR/.config/swayidle/config"
chmod +x "$HOME_DIR/.config/waybar/scripts/"*.py "$HOME_DIR/.config/waybar/scripts/"*.sh
# Seed RAM/VRAM cache as root (dmidecode). Later board/GPU changes re-probe.
python3 - <<PY
import os, sys
sys.path.insert(0, "${REPO}/waybar/scripts")
os.environ["HOME"] = "${HOME_DIR}"
from lib import hw_info
print(hw_info())
PY
chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.cache/waybar"
gcc -O2 -o "$HOME_DIR/.config/waybar/scripts/kbgroup" "$REPO/waybar/scripts/kbgroup.c" $(pkg-config --cflags --libs wayland-client)
gcc -O2 -o "$HOME_DIR/.config/waybar/scripts/layout-watch" "$REPO/waybar/scripts/layout-watch.c" $(pkg-config --cflags --libs xkbcommon)
cp "$HOME_DIR/.config/waybar/scripts/kbgroup" "$HOME_DIR/.config/waybar/scripts/layout-watch" "$HOME_DIR/appearance/waybar/scripts/"
if [ -n "${KEYBOARD_UNIQ:-}" ]; then
	umask 022
	cat > /etc/udev/rules.d/99-layout-watch.rules <<EOF
ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ATTRS{uniq}=="${KEYBOARD_UNIQ}", RUN+="/usr/bin/setfacl -m u:${USER_NAME}:r /dev/%k"
EOF
	udevadm control --reload
fi

cp "$REPO/start-dwl.sh" "$HOME_DIR/appearance/start-dwl.sh"
chmod +x "$HOME_DIR/appearance/start-dwl.sh" "$REPO/start-dwl.sh"

# mihomo + tui (no proxy nodes — merge those locally)
install -d "$HOME_DIR/.config/mihomo" "$HOME_DIR/.config/mihomo-tui" \
	"$HOME_DIR/.config/systemd/user/mihomo.service.d" \
	"$HOME_DIR/.local/bin" "$HOME_DIR/.local/share/applications"
if [ ! -f "$HOME_DIR/.config/mihomo/config.yaml" ]; then
	install -m 644 "$REPO/mihomo/config.yaml" "$HOME_DIR/.config/mihomo/config.yaml"
fi
install -m 644 "$REPO/mihomo/mihomo-tui/config.yaml" "$HOME_DIR/.config/mihomo-tui/config.yaml"
install -m 644 "$REPO/mihomo/systemd/mihomo.service" "$HOME_DIR/.config/systemd/user/mihomo.service"
install -m 644 "$REPO/mihomo/systemd/system-proxy.conf" "$HOME_DIR/.config/systemd/user/mihomo.service.d/"
install -m 644 "$REPO/mihomo/systemd/tun-ipv6.conf" "$HOME_DIR/.config/systemd/user/mihomo.service.d/"
install -m 755 "$REPO/mihomo/bin/"* "$HOME_DIR/.local/bin/"
install -m 644 "$REPO/mihomo/desktop/mihomo-tui.desktop" "$HOME_DIR/.local/share/applications/"
chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.config/mihomo" "$HOME_DIR/.config/mihomo-tui" \
	"$HOME_DIR/.config/systemd/user/mihomo.service" "$HOME_DIR/.config/systemd/user/mihomo.service.d" \
	"$HOME_DIR/.local/bin" "$HOME_DIR/.local/share/applications/mihomo-tui.desktop"
# TUN as user (idempotent)
if command -v setcap >/dev/null 2>&1 && [ -x /usr/bin/mihomo ]; then
	setcap 'cap_net_admin,cap_net_raw,cap_net_bind_service=+ep' /usr/bin/mihomo || true
fi
runuser -u "$USER_NAME" -- systemctl --user daemon-reload
runuser -u "$USER_NAME" -- systemctl --user enable mihomo.service
#cp config.h "$HOME_DIR/dwl/"
#cp wallpaper.png "$HOME_DIR/appearance"

#sudo pacman -S firefox libreoffice
echo "we're done"



#below is test field, if some command will help
systemctl --user enable --now pipewire wireplumber

#for vm's
#sudo pacman -S qemu-full virt-manager libvirt polkit dmidecode dnsmasq
#stirling pdf should be deployed on a home server
