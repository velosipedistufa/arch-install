# Copy to globals.sh and edit. globals.sh is gitignored — do not commit it.
#   cp globals.example.sh globals.sh
#
# Install scripts:  . ./globals.sh
# Waybar: reads the same file (or ~/.config/arch-install/globals.sh after setup.sh).

# Login user created by archinstall2.sh / used by setup.sh
USER_NAME=youruser
USER_PASSWORD=changeme
HOSTNAME=arch

# YOU set this. Whole disk, not a partition (not nvme0n1p1, not sda1).
# archinstall1.sh adds the partition suffix itself:
#   /dev/nvme0n1  →  nvme0n1p1 EFI, nvme0n1p2 root
#   /dev/sda      →  sda1 EFI, sda2 root
#   /dev/vda      →  vda1 / vda2  (typical VM)
DISK=/dev/sda

# LAN host to ping on the bar (home server). Short label is the plate text.
HOME_SERVER=192.168.1.10
HOME_SERVER_LABEL=home
# Optional. Empty = derive x.y.z.255 from HOME_SERVER.
LAN_BCAST=

# Remote VPS: DNS name plus the A / AAAA you expect. Bar checks DoH matches
# these addresses, then pings the addresses (not the name — avoids fake-ip).
VPS_HOST=vps.example.com
VPS_A=203.0.113.10
VPS_AAAA=2001:db8::10
VPS_LABEL=VPS

# Keyboard evdev for layout-watch (display only). Empty = skip watcher.
KEYBOARD_EVENT=
# udev ATTRS{uniq} so the user can read that node after replug. Empty = skip rule.
KEYBOARD_UNIQ=

# RAM type (DDR3/4/5) and VRAM type (GDDR5/…) are not set here.
# Detected from DMI / amdgpu on first run and whenever the board or GPU changes.

# Screenshots (Print): grim+slurp region → clipboard, local dir, Nextcloud.
# Use the public hostname (cloud.example.com), never a LAN IP, so a laptop
# off-LAN still uploads. Per-machine folder: ScreenshotsDesktop vs ScreenshotsLaptop.
SCREENSHOT_LOCAL_DIR=/tmp/screenshots
SCREENSHOT_DAV_URL=https://cloud.example.com/remote.php/dav/files/youruser/Pictures/ScreenshotsDesktop
SCREENSHOT_DAV_USER=youruser
SCREENSHOT_DAV_PASSWORD=changeme
