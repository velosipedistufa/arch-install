#!/bin/bash
# Stage 2, run on the installed system after the reboot.
# Packages, dwl, and the session. Configs are symlinked from this checkout.
set -euo pipefail
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

[[ ! -d /run/archiso ]] || die "Run install-base.sh from the live ISO. install-desktop.sh runs after you have rebooted into the new system."

need_root
if [[ -f /var/lib/pacman/db.lck ]] && ! pgrep -x pacman >/dev/null; then
	rm -f /var/lib/pacman/db.lck
fi
load_secrets
require_var USER_NAME
require_var USER_PASSWORD

id -u "$USER_NAME" >/dev/null 2>&1 || die "User $USER_NAME does not exist. install-base.sh creates that account."
REPO=$HERE
HOME_DIR="/home/${USER_NAME}"
[[ -d $HOME_DIR ]] || die "Missing $HOME_DIR"
# install -d as root leaves ~/.cache owned by root, and paru cannot create
# ~/.cache/paru there. Hand the directories the user will write to back.
install -d "${HOME_DIR}/.cache/paru" "${HOME_DIR}/.cache/arch-install" \
	"${HOME_DIR}/.config" "${HOME_DIR}/.local/bin"
chown -R "$USER_NAME:$USER_NAME" "${HOME_DIR}/.cache" "${HOME_DIR}/.config" "${HOME_DIR}/.local"

# paru calls sudo as the user. The drop-in is removed on the way out, including on failure.
enable_build_sudo() {
	install -Dm440 /dev/stdin /etc/sudoers.d/99-arch-install-build <<EOF
${USER_NAME} ALL=(ALL) NOPASSWD: ALL
EOF
	visudo -cf /etc/sudoers.d/99-arch-install-build >/dev/null
}
disable_build_sudo() {
	rm -f /etc/sudoers.d/99-arch-install-build
	sync
}
trap disable_build_sudo EXIT

pacman_do() {
	local cache conf
	cache=$(pkg_cache_dir)
	if [[ -z $cache ]]; then
		pacman "$@"
		return
	fi
	log "Using package cache $cache"
	conf=$(mktemp)
	write_pacman_conf "$conf" "$cache"
	pacman --config "$conf" "$@"
	rm -f "$conf"
}

link_path() {
	local src=$1 dst=$2
	[[ -e $src ]] || die "Missing $src"
	install -d -o "$USER_NAME" -g "$USER_NAME" "$(dirname "$dst")"
	if [[ -e $dst && ! -L $dst ]]; then
		rm -rf "$dst"
	fi
	ln -sfn "$src" "$dst"
}

# makepkg and paru call pacman without --config. Record the extra cache on the
# system config so those builds reuse it. The first CacheDir stays the writable one.
pkg_cache=$(pkg_cache_dir)
if [[ -n $pkg_cache ]]; then
	pkg_conf=$(mktemp)
	write_pacman_conf "$pkg_conf" "$pkg_cache"
	install -m 644 "$pkg_conf" /etc/pacman.conf
	rm -f "$pkg_conf"
fi

log "Installing official packages"
mapfile -t desktop_pkgs < <(read_packages "$REPO/packages/desktop.txt")
pacman_do -Syu --needed --noconfirm "${desktop_pkgs[@]}"

chmod +x "$REPO/start-dwl.sh" "$REPO/session/ly-start-dwl" \
	"$REPO/waybar/scripts/"*.sh "$REPO/waybar/scripts/dnd-key.py" \
	"$REPO/yazi/bin/"* "$REPO/mihomo/bin/"*

enable_build_sudo
# paru --sudoloop runs `sudo -v`. That still asks for a password when the
# command itself is NOPASSWD, and on a serial console nobody answers it.
as_user sudo -n true || die "Passwordless sudo for ${USER_NAME} did not take effect."
log "Installing paru"
# paru-bin is built against an older libalpm and will not start. Build paru
# from source so it links to this machine's pacman.
paru_ok=0
if as_user /usr/bin/paru --version >/tmp/paru-version.txt 2>&1; then
	if grep -q '^paru ' /tmp/paru-version.txt; then
		paru_ok=1
	fi
fi
cat /tmp/paru-version.txt || true
if [[ $paru_ok -ne 1 ]]; then
	src="${HOME_DIR}/.cache/arch-install/paru"
	# A killed VM can leave a zero-length archive that still matches the glob.
	collect_paru_pkgs() {
		local pkg
		built=()
		shopt -s nullglob
		for pkg in "$src"/paru-[0-9]*.pkg.tar.zst; do
			if [[ -s $pkg ]] && bsdtar -tf "$pkg" .PKGINFO >/dev/null 2>&1; then
				built+=("$pkg")
			fi
		done
		shopt -u nullglob
	}
	collect_paru_pkgs
	if [[ ${#built[@]} -eq 0 ]]; then
		rm -rf "$src"
		install -d -o "$USER_NAME" -g "$USER_NAME" "$(dirname "$src")"
		as_user git clone --depth 1 https://aur.archlinux.org/paru.git "$src"
		# runuser drops the caller environment, so the job cap has to be set
		# on the far side of it. One cargo job stays inside a small VM.
		(cd "$src" && as_user env CARGO_BUILD_JOBS=1 makepkg --noconfirm --noprogressbar --syncdeps)
		# The package file must hit the disk before anything else. A killed VM
		# otherwise leaves a zero-length archive.
		sync
		collect_paru_pkgs
	else
		log "Reusing the paru package already built in $src"
	fi
	[[ ${#built[@]} -gt 0 ]] || die "paru did not produce a readable package."
	# paru-bin owns the same paths and is linked to an older libalpm.
	# Remove each name on its own so a missing debug package does not cancel the removal.
	if pacman -Qq paru-bin >/dev/null 2>&1; then
		pacman -Rdd --noconfirm paru-bin
	fi
	if pacman -Qq paru-bin-debug >/dev/null 2>&1; then
		pacman -Rdd --noconfirm paru-bin-debug
	fi
	pacman -U --noconfirm --overwrite '*' "${built[@]}"
	sync
	sync
fi

log "Installing AUR packages"
mapfile -t aur_pkgs < <(read_packages "$REPO/packages/aur.txt")
[[ ${#aur_pkgs[@]} -gt 0 ]] || die "packages/aur.txt has no packages."
log "AUR: ${aur_pkgs[*]}"
# A fresh install has none of the AUR maintainers' keys, and this script is not
# interactive. Skip the PGP prompt and the signature check. --nocheck skips
# upstream test suites. Output stays on the console so a long build is visible.
if ! as_user paru -S --noconfirm --needed --skipreview --nocheck \
	--nopgpfetch --failfast --mflags "--skippgpcheck" "${aur_pkgs[@]}" \
	2>&1 | tee /tmp/paru-install.log; then
	die "paru failed. See /tmp/paru-install.log in the install environment."
fi
pacman -Q wlroots0.19 >/dev/null || die "wlroots0.19 is not installed."

log "Building dwl"
ref=$(grep -E '^[0-9a-f]{40}$' "$REPO/dwl/UPSTREAM" | head -1)
[[ -n $ref ]] || die "dwl/UPSTREAM has no commit hash."
src="${HOME_DIR}/.cache/arch-install/dwl"
rm -rf "$src"
install -d -o "$USER_NAME" -g "$USER_NAME" "$(dirname "$src")"
as_user git clone --depth 1 --branch v0.8 https://codeberg.org/dwl/dwl "$src"
got=$(git -C "$src" rev-parse HEAD)
[[ $got == "$ref" ]] || die "dwl v0.8 is $got, expected $ref. Update dwl/UPSTREAM and the layout patch together."
install -m 644 -o "$USER_NAME" -g "$USER_NAME" "$REPO/dwl/config.h" "$src/config.h"
patch -d "$src" -p1 --forward <"$REPO/patches/dwl-layout-file.patch"
as_user make -C "$src"
install -d -o "$USER_NAME" -g "$USER_NAME" "${HOME_DIR}/.local/bin"
install -m 755 -o "$USER_NAME" -g "$USER_NAME" "$src/dwl" "${HOME_DIR}/.local/bin/dwl"

log "Building waybar helpers"
# shellcheck disable=SC2046
gcc -O2 -o "${HOME_DIR}/.local/bin/kbgroup" "$REPO/waybar/scripts/kbgroup.c" $(pkg-config --cflags --libs wayland-client)
# shellcheck disable=SC2046
gcc -O2 -o "${HOME_DIR}/.local/bin/layout-watch" "$REPO/waybar/scripts/layout-watch.c" $(pkg-config --cflags --libs xkbcommon)
chown "$USER_NAME:$USER_NAME" "${HOME_DIR}/.local/bin/kbgroup" "${HOME_DIR}/.local/bin/layout-watch"

log "Linking configs from $REPO"
install -d -o "$USER_NAME" -g "$USER_NAME" -m 700 "${HOME_DIR}/.config/arch-install"
install -m 600 -o "$USER_NAME" -g "$USER_NAME" "$SECRETS_FILE" "${HOME_DIR}/.config/arch-install/secrets.sh"
chmod 600 "$SECRETS_FILE"

link_path "$REPO/waybar/config.jsonc" "${HOME_DIR}/.config/waybar/config.jsonc"
link_path "$REPO/waybar/style.css" "${HOME_DIR}/.config/waybar/style.css"
link_path "$REPO/waybar/scripts" "${HOME_DIR}/.config/waybar/scripts"
link_path "$REPO/mako/config" "${HOME_DIR}/.config/mako/config"
link_path "$REPO/swayidle/config" "${HOME_DIR}/.config/swayidle/config"
link_path "$REPO/swaylock/config" "${HOME_DIR}/.config/swaylock/config"
link_path "$REPO/zsh/.zshrc" "${HOME_DIR}/.zshrc"
link_path "$REPO/xdg-desktop-portal/portals.conf" "${HOME_DIR}/.config/xdg-desktop-portal/portals.conf"
link_path "$REPO/xdg-desktop-portal-wlr/config" "${HOME_DIR}/.config/xdg-desktop-portal-wlr/config"
link_path "$REPO/start-dwl.sh" "${HOME_DIR}/.local/bin/start-dwl"
link_path "$REPO/yazi/yazi.toml" "${HOME_DIR}/.config/yazi/yazi.toml"
link_path "$REPO/yazi/keymap.toml" "${HOME_DIR}/.config/yazi/keymap.toml"
link_path "$REPO/yazi/init.lua" "${HOME_DIR}/.config/yazi/init.lua"
link_path "$REPO/yazi/plugins/usb.yazi" "${HOME_DIR}/.config/yazi/plugins/usb.yazi"
link_path "$REPO/yazi/bin/yazi-usb-watch" "${HOME_DIR}/.local/bin/yazi-usb-watch"
link_path "$REPO/yazi/bin/nextcloud-ensure" "${HOME_DIR}/.local/bin/nextcloud-ensure"
link_path "$REPO/systemd/user/dnd-key.service" "${HOME_DIR}/.config/systemd/user/dnd-key.service"
link_path "$REPO/systemd/user/yazi-usb-watch.service" "${HOME_DIR}/.config/systemd/user/yazi-usb-watch.service"
link_path "$REPO/systemd/user/nextcloud-mount.service" "${HOME_DIR}/.config/systemd/user/nextcloud-mount.service"
link_path "$REPO/mihomo/systemd/mihomo.service" "${HOME_DIR}/.config/systemd/user/mihomo.service"
link_path "$REPO/mihomo/systemd/system-proxy.conf" "${HOME_DIR}/.config/systemd/user/mihomo.service.d/system-proxy.conf"
link_path "$REPO/mihomo/systemd/tun-ipv6.conf" "${HOME_DIR}/.config/systemd/user/mihomo.service.d/tun-ipv6.conf"
link_path "$REPO/mihomo/systemd/skoltech-dns-fwd.service" "${HOME_DIR}/.config/systemd/user/skoltech-dns-fwd.service"
link_path "$REPO/mihomo/desktop/mihomo-tui.desktop" "${HOME_DIR}/.local/share/applications/mihomo-tui.desktop"
for bin in "$REPO/mihomo/bin/"*; do
	link_path "$bin" "${HOME_DIR}/.local/bin/$(basename "$bin")"
done
if [[ ! -e ${HOME_DIR}/.config/mihomo/config.yaml ]]; then
	install -d -o "$USER_NAME" -g "$USER_NAME" "${HOME_DIR}/.config/mihomo"
	install -m 644 -o "$USER_NAME" -g "$USER_NAME" "$REPO/mihomo/config.yaml" "${HOME_DIR}/.config/mihomo/config.yaml"
fi
install -d -o "$USER_NAME" -g "$USER_NAME" "${HOME_DIR}/.config/mihomo-tui"
if [[ ! -e ${HOME_DIR}/.config/mihomo-tui/config.yaml ]]; then
	install -m 644 -o "$USER_NAME" -g "$USER_NAME" "$REPO/mihomo/mihomo-tui/config.yaml" "${HOME_DIR}/.config/mihomo-tui/config.yaml"
fi

if [[ -n ${HOME_SERVER:-} && ! -e ${HOME_DIR}/.config/yazi/vfs.toml ]]; then
	umask 077
	cat >"${HOME_DIR}/.config/yazi/vfs.toml" <<EOF
[sftp.nas]
host     = "${HOME_SERVER}"
user     = "${USER_NAME}"
port     = 22
password = "${USER_PASSWORD}"
EOF
	chown "$USER_NAME:$USER_NAME" "${HOME_DIR}/.config/yazi/vfs.toml"
	chmod 600 "${HOME_DIR}/.config/yazi/vfs.toml"
fi

install -d -o "$USER_NAME" -g "$USER_NAME" "${HOME_DIR}/.local/mnt/nextcloud" "${HOME_DIR}/.cache/waybar"
if HOME="$HOME_DIR" python3 - "$REPO" "$HOME_DIR" <<'PY'
import os, sys
repo, home = sys.argv[1:]
sys.path.insert(0, repo + "/waybar/scripts")
os.environ["HOME"] = home
from lib import hw_info
print(hw_info())
PY
then
	chown -R "$USER_NAME:$USER_NAME" "${HOME_DIR}/.cache/waybar" || true
else
	log "RAM/VRAM probe did not finish. The bar fills the cache on the next login."
fi

log "Installing session files and udev rules"
install -m 755 "$REPO/session/ly-start-dwl" /usr/local/bin/start-dwl
install -d /usr/share/wayland-sessions
install -m 644 "$REPO/wayland-sessions/dwl.desktop" /usr/share/wayland-sessions/dwl.desktop
install -m 644 "$REPO/udev/90-backlight.rules" /etc/udev/rules.d/90-backlight.rules
if [[ -n ${KEYBOARD_UNIQ:-} ]]; then
	cat >/etc/udev/rules.d/99-layout-watch.rules <<EOF
ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ATTRS{uniq}=="${KEYBOARD_UNIQ}", RUN+="/usr/bin/setfacl -m u:${USER_NAME}:r /dev/%k"
EOF
	chmod 644 /etc/udev/rules.d/99-layout-watch.rules
fi
udevadm control --reload || true
usermod -aG video "$USER_NAME" || true

if [[ -f $REPO/mihomo/pacman/mihomo-setcap.hook ]]; then
	install -d /etc/pacman.d/hooks
	install -m 644 "$REPO/mihomo/pacman/mihomo-setcap.hook" /etc/pacman.d/hooks/mihomo-setcap.hook
fi
if [[ -x /usr/bin/mihomo ]]; then
	setcap 'cap_net_admin,cap_net_raw,cap_net_bind_service=+ep' /usr/bin/mihomo || log "setcap on mihomo failed; TUN may stay off until the pacman hook runs."
fi

# Work VPN unit. The password stays in secrets.sh. Skip when those fields are empty.
if [[ -n ${SKOLTECH_VPN_USER:-} && -n ${SKOLTECH_VPN_PASSWORD:-} && -n ${SKOLTECH_VPN_SERVER:-} ]]; then
	"$REPO/mihomo/bin/skoltech-install" || log "skoltech VPN did not start."
else
	systemctl disable --now skoltech-vpn.service 2>/dev/null || true
fi

log "Setting 0xProto Nerd Font as the desktop default"
# ttf-iosevka-nerd is already installed with the desktop packages. It is the
# Cyrillic fallback; 0xProto has no Cyrillic. Drop a leftover hand copy so it
# does not shadow the package.
rm -rf /usr/local/share/fonts/iosevka-nerd
install -d /etc/fonts/conf.d
install -m 644 "$REPO/fontconfig/local.conf" /etc/fonts/local.conf
ln -sfn /etc/fonts/local.conf /etc/fonts/conf.d/00-arch-install-0xproto.conf
fc-cache -f || log "fontconfig cache refresh failed."
fc-list "Iosevka Nerd Font Mono" file | grep -q . \
	|| die "Iosevka Nerd Font Mono is not visible to fontconfig."

as_user dbus-run-session gsettings set org.gnome.desktop.interface gtk-theme 'Flat-Remix-GTK-Red-Darkest' \
	|| log "GTK theme was not applied."
as_user dbus-run-session gsettings set org.gnome.desktop.interface icon-theme 'Flat-Remix-Red-Dark' \
	|| log "Icon theme was not applied."
as_user dbus-run-session gsettings set org.gnome.desktop.interface font-name '0xProto Nerd Font 11' \
	|| log "Interface font was not applied."
as_user dbus-run-session gsettings set org.gnome.desktop.interface document-font-name '0xProto Nerd Font 11' \
	|| log "Document font was not applied."
as_user dbus-run-session gsettings set org.gnome.desktop.interface monospace-font-name '0xProto Nerd Font 11' \
	|| log "Monospace font was not applied."

install -d -o "$USER_NAME" -g "$USER_NAME" "${HOME_DIR}/.config/gtk-3.0" "${HOME_DIR}/.config/gtk-4.0" \
	"${HOME_DIR}/.config/kitty" "${HOME_DIR}/.config/fuzzel"
gtk_ini="${HOME_DIR}/.config/gtk-3.0/settings.ini"
if [[ ! -f $gtk_ini ]]; then
	printf '%s\n' '[Settings]' >"$gtk_ini"
fi
if grep -q '^gtk-font-name=' "$gtk_ini"; then
	sed -i 's/^gtk-font-name=.*/gtk-font-name=0xProto Nerd Font 11/' "$gtk_ini"
else
	printf '%s\n' 'gtk-font-name=0xProto Nerd Font 11' >>"$gtk_ini"
fi
chown "$USER_NAME:$USER_NAME" "$gtk_ini"
# gtk-4.0 is mode 700. The settings file itself stays world-readable.
install -m 644 -o "$USER_NAME" -g "$USER_NAME" /dev/stdin "${HOME_DIR}/.config/gtk-4.0/settings.ini" <<'EOF'
[Settings]
gtk-font-name=0xProto Nerd Font 11
EOF

# Keep any other kitty or fuzzel options. A second run replaces these lines.
set_conf_line() {
	local file=$1 key=$2 value=$3
	touch "$file"
	if grep -q "^${key}" "$file"; then
		sed -i "s|^${key}.*|${key}${value}|" "$file"
	else
		printf '%s%s\n' "$key" "$value" >>"$file"
	fi
	chown "$USER_NAME:$USER_NAME" "$file"
}
set_conf_line "${HOME_DIR}/.config/kitty/kitty.conf" 'font_family ' '0xProto Nerd Font'
set_conf_line "${HOME_DIR}/.config/kitty/kitty.conf" 'font_size ' '11.0'
set_conf_line "${HOME_DIR}/.config/fuzzel/fuzzel.ini" 'font=' '0xProto Nerd Font:size=11'

swayimg_lua="${HOME_DIR}/.config/swayimg/init.lua"
if [[ -f $swayimg_lua ]] && grep -q 'swayimg.text.font' "$swayimg_lua"; then
	sed -i 's/swayimg\.text\.font = ".*"/swayimg.text.font = "0xProto Nerd Font"/' "$swayimg_lua"
fi

systemctl enable ly@tty2.service
systemctl disable getty@tty2.service || true
systemctl enable bluetooth.service
systemctl start bluetooth.service || log "bluetooth did not start. That is normal with no adapter."

loginctl enable-linger "$USER_NAME"
systemctl start "user@$(id -u "$USER_NAME").service"
# systemctl --user needs the per-user bus, which appears after the user manager starts.
uid=$(id -u "$USER_NAME")
for _ in $(seq 1 25); do
	[[ -S /run/user/${uid}/bus ]] && break
	sleep 0.2
done
[[ -S /run/user/${uid}/bus ]] || die "User bus for ${USER_NAME} did not start."
as_user systemctl --user daemon-reload
as_user systemctl --user enable pipewire.service wireplumber.service mihomo.service skoltech-dns-fwd.service
as_user systemctl --user enable yazi-usb-watch.service
if [[ -n ${KEYBOARD_UNIQ:-} || -n ${KEYBOARD_EVENT:-} ]]; then
	as_user systemctl --user enable dnd-key.service
fi
if [[ -n ${SCREENSHOT_DAV_URL:-} && $SCREENSHOT_DAV_URL != *example.com* ]]; then
	as_user "${HOME_DIR}/.local/bin/nextcloud-ensure" || log "Nextcloud was not mounted. Check SCREENSHOT_DAV_* and the network."
	as_user systemctl --user enable nextcloud-mount.service || true
fi

# install-base.sh already sets the login shell. chsh complains if it is unchanged.
if [[ $(getent passwd "$USER_NAME" | cut -d: -f7) != /usr/bin/zsh ]]; then
	chsh -s /usr/bin/zsh "$USER_NAME"
fi
disable_build_sudo
trap - EXIT

cat <<EOF

INSTALL_DESKTOP_OK

Desktop install finished for ${USER_NAME}.
This checkout (${REPO}) is the source of truth. Waybar, mako, yazi, zsh, and the session script are symlinks into it.
dwl is ${HOME_DIR}/.local/bin/dwl. ly is enabled on tty2 and was not started.

Reboot, or switch to tty2, and log in. The session is dwl.
Colemak is the console keymap. Inside dwl, Ctrl+Shift switches us (colemak) and ru.
EOF
