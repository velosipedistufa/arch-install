# Copy to secrets.sh and edit. secrets.sh is gitignored. Do not commit it.
#   cp secrets.example.sh secrets.sh
#
# install-base.sh and install-desktop.sh source ./secrets.sh (or $ARCH_INSTALL_SECRETS).
# After install-desktop.sh, programs read ~/.config/arch-install/secrets.sh.
# If that file is absent they still accept the previous name, globals.sh.
#
# Switch the console to colemak before you type the password here, so the
# characters you enter are the ones the colemak login will produce.
#
# install-base.sh refuses USER_NAME=youruser and USER_PASSWORD=changeme.

USER_NAME=youruser
USER_PASSWORD=changeme
HOSTNAME=arch

# Optional. Defaults are en_US.UTF-8 and UTC.
LOCALE=en_US.UTF-8
TIMEZONE=UTC

# Whole disk, not a partition. install-base.sh erases it.
#   /dev/nvme0n1  ->  nvme0n1p1 EFI, nvme0n1p2 root
#   /dev/sda      ->  sda1 EFI, sda2 root
#   /dev/vda      ->  vda1 EFI, vda2 root
# Leave this empty until you have chosen the disk. An empty value aborts.
DISK=

# Home server IPv6: this PC's current ISP /64 (not stored) plus ::IID.
# The waybar plate shows HOME_SERVER_LABEL.
HOME_SERVER_IID=6
HOME_SERVER_LABEL=::6
# Optional IPv4, used for LAN checks and the yazi SFTP mount. Empty skips both.
HOME_SERVER=
# Optional. Empty = derive x.y.z.255 from HOME_SERVER.
LAN_BCAST=

# Remote VPS. The bar checks DNS-over-HTTPS for these addresses, then pings them.
VPS_HOST=vps.example.com
VPS_A=203.0.113.10
VPS_AAAA=2001:db8::10
VPS_LABEL=VPS

# Keyboard evdev node for the layout watcher. Empty skips the watcher.
KEYBOARD_EVENT=
# udev ATTRS{uniq} so this user can read the node after replug. Empty skips the rule.
KEYBOARD_UNIQ=

# RAM type (DDR3/4/5) and VRAM type are not set here.
# They are probed from the machine and cached under ~/.cache/waybar.

# Work VPN (Cisco AnyConnect). OpenConnect keeps a tun named ocsk.
# Mihomo selects it as the "skoltech" node. Empty user or password skips the service.
# The password stays in this file. Do not copy it into mihomo/config.yaml.
# Leave SKOLTECH_VPN_SERVERCERT empty to pin whatever leaf the gateway presents
# (the chain does not verify). Set pin-sha256:... to pin one certificate.
SKOLTECH_VPN_SERVER=vpn.skoltech.ru
SKOLTECH_VPN_USER=
SKOLTECH_VPN_PASSWORD=
SKOLTECH_VPN_SERVERCERT=

# Screenshots: grim+slurp region, then clipboard, a local dir, and WebDAV.
# Use a public hostname, not a LAN address, so a laptop off-LAN can upload.
SCREENSHOT_LOCAL_DIR=/tmp/screenshots
SCREENSHOT_DAV_URL=https://cloud.example.com/remote.php/dav/files/youruser/Pictures/Screenshots
SCREENSHOT_DAV_USER=youruser
SCREENSHOT_DAV_PASSWORD=changeme
