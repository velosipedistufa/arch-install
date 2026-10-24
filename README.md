# arch-install

Two-stage Arch install for a colemak console and a dwl / Waybar session.

The git checkout is the source of truth for scripts, `dwl/config.h`, the layout patch, and the config files. `install-desktop.sh` symlinks those into `~/.config` and `~/.local`. It does not keep a second copy of the tree.

Build outputs go to `~/.cache/arch-install`. VM disks and the package cache belong outside the repo (this machine uses `/mnt/gentoo`).

## Install

On the Arch live ISO:

```sh
git clone https://github.com/velosipedistufa/arch-install
cd arch-install
./colemak.sh
cp secrets.example.sh secrets.sh
$EDITOR secrets.sh
sudo ./install-base.sh
```

`colemak.sh` switches the console from qwerty to colemak. Run it before you type the password into `secrets.sh`, so the characters you store are the ones the colemak login will produce.

`install-base.sh` erases `DISK`, installs a bootable system, and returns. It does not reboot. It prints the remaining steps: power off, eject the install medium, boot the new disk, then:

```sh
cd ~/GitRepos/arch-install
sudo ./install-desktop.sh
```

The console keymap on that boot is colemak (`KEYMAP=colemak` in `/etc/vconsole.conf`). Inside dwl, the layout is us (colemak) plus ru, toggled with Ctrl+Shift. That is separate from the console keymap and lives in `dwl/config.h`.

`install-desktop.sh` installs packages, builds paru from source (the prebuilt `paru-bin` package does not match the current libalpm), builds dwl v0.8 against wlroots 0.19, enables ly on tty2, and links the session into the standard paths. ly is not started for you. Reboot, or switch to tty2, and pick dwl.

The desktop font is 0xProto Nerd Font (`ttf-0xproto-nerd`). `fontconfig/local.conf` is installed as `/etc/fonts/local.conf`, so `sans`, `serif`, and `monospace` resolve to it. GTK, kitty, fuzzel, waybar, mako, and swaylock use the same face. Cyrillic falls back to Iosevka Nerd Font Mono from `ttf-iosevka-nerd`. That fallback is limited to Cyrillic, so icons and other missing glyphs stay on 0xProto or Symbols Nerd Font. Noto Color Emoji remains the emoji font. KiCad is left on KiCad Font.

## Secrets

`secrets.sh` is the only local config file. It holds the username, password, hostname, disk, addresses, and keyboard id. It is gitignored.

```sh
cp secrets.example.sh secrets.sh
```

Install scripts read `./secrets.sh`, or the file named by `ARCH_INSTALL_SECRETS`. `install-desktop.sh` installs a mode `0600` copy at `~/.config/arch-install/secrets.sh`. Waybar, screenshots, and the Nextcloud helper read that copy. If it is missing they still accept `globals.sh`, the previous filename.

`install-base.sh` asks you to type the disk path before it erases anything. It refuses a disk that has a mounted filesystem. `ARCH_INSTALL_YES=1` skips the prompt and is for the QEMU test.

Do not commit `secrets.sh`, `globals.sh`, or a generated udev rule that contains a keyboard serial.

## Package cache

Repeated installs can reuse one pacman cache. On a machine with room outside the root disk:

```sh
sudo mkdir -p /mnt/gentoo/arch-pkg-cache
sudo ./cache-packages.sh
```

`cache-packages.sh` runs `pacman -Syw --cachedir` for `packages/base.txt` and `packages/desktop.txt`. Packages in `packages/aur.txt`, and paru itself, are built by `install-desktop.sh`. Their sources are not in this cache. When the cache directory exists, `install-desktop.sh` adds it as a second `CacheDir` in `/etc/pacman.conf`, so `makepkg` reuses it too. Pacman still writes new downloads to `/var/cache/pacman/pkg`.

`install-base.sh` and `install-desktop.sh` use `/mnt/gentoo/arch-pkg-cache` when that directory exists. Point `PACMAN_CACHE` at another directory to override it. Pacman still refreshes the repository databases, and it downloads a package only when the cache does not already have that version.

## What lands where

| Path | Role |
|---|---|
| `colemak.sh` | Console keymap, live ISO or installed system |
| `install-base.sh` | Partition, pacstrap, bootloader, user, colemak. Stops before reboot |
| `install-desktop.sh` | Packages, dwl, ly, symlinks |
| `cache-packages.sh` | Fill the pacman cache |
| `dwl/config.h` | dwl configuration copied into the build tree |
| `dwl/UPSTREAM` | dwl v0.8 commit the patch applies to |
| `~/.local/bin/dwl` | Built binary |
| `~/.local/bin/start-dwl` | Symlink to `start-dwl.sh` |
| `/usr/local/bin/start-dwl` | ly's entry point; execs the symlink above |
| `~/.config/waybar`, `~/.config/mako`, `~/.config/yazi`, `~/.zshrc` | Symlinks into this checkout |
| `~/.config/mihomo/config.yaml` | Copied once, so local proxy nodes are not overwritten |
| `~/.cache/arch-install/` | dwl and paru build trees |

dwl is cloned into the cache and patched there. The `dwl/` directory in this repo is only `config.h` and the pinned commit.

## QEMU

`tools/qemu-test.py` boots the current Arch ISO with OVMF, runs stage 1, boots the installed disk, checks that colemak is loaded, and runs stage 2.

```sh
python3 tools/qemu-test.py phase1
python3 tools/qemu-test.py phase2
python3 tools/qemu-test.py all
```

Disks, firmware vars, and logs go to `/mnt/gentoo/arch-install-vm/`. The ISO used by the script is `archlinux-2026.09.01-x86_64.iso` in that directory. The test account is `qa` / `1234` (those characters match on qwerty and colemak). KVM is used when `/dev/kvm` exists; otherwise QEMU runs in TCG and stage 2 is slow.

The test is not part of a normal install. `tools/guest-phase1.sh` and `tools/guest-phase2.sh` exit unless the vendor is QEMU.

## Layout of the session

ly on tty2 starts `/usr/local/bin/start-dwl`, which runs `start-dwl.sh`. That starts dwl, the portals (including xdg-desktop-portal-wlr for Firefox screen share), mako, waybar, swaybg, and swayidle. The wallpaper is `wallpaper.png` in this checkout.

Mihomo's program config is under `mihomo/`. Proxy profiles are not in git. The work VPN is the `skoltech` node; its password stays in `secrets.sh`. See [`mihomo/README.md`](mihomo/README.md).
