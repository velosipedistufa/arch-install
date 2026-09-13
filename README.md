# arch-install

Arch (and a bit of Debian) install + dwl/Waybar session.

## Private data (`globals.sh`)

Site-specific values live in **one file**. It is not committed.

```sh
cp globals.example.sh globals.sh
$EDITOR globals.sh
```

| Variable | Used for |
|---|---|
| `USER_NAME` / `USER_PASSWORD` | `archinstall2.sh` user + password (placeholders in the example) |
| `HOSTNAME` | `/etc/hostname` |
| `DISK` | **You pick this.** Whole disk only (`/dev/nvme0n1`, `/dev/sda`, `/dev/vda`). The install script invents `p1`/`1` itself. |
| `HOME_SERVER` / `HOME_SERVER_LABEL` | Waybar home-host ping |
| `VPS_HOST` / `VPS_A` / `VPS_AAAA` | Waybar VPS plate: DoH A/AAAA must match, then ping those IPs |
| `KEYBOARD_EVENT` / `KEYBOARD_UNIQ` | layout-watch (display only) |

RAM (DDR3/4/5) and VRAM (GDDR…) are **not** in globals — probed from the machine, cached, and refreshed if the board or GPU changes.

Install scripts `source` this file. Waybar Python modules parse the same file (repo `globals.sh` or `~/.config/arch-install/globals.sh` after `setup.sh`).

Override path: `ARCH_INSTALL_GLOBALS=/path/to/globals.sh`.

## Layout

1. Live ISO: edit `globals.sh`, run `archinstall1.sh`, then in chroot `archinstall2.sh`.
2. As root on the installed system: `setup.sh` (paru, dwl, Waybar, ly).
3. Session: ly → `start-dwl.sh`.

Do not commit `globals.sh` or `forGrok.md`.
