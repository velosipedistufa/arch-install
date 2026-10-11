#!/usr/bin/env python3
"""Boot the two-stage install in QEMU.

Large files stay on /mnt/gentoo. KVM is used when /dev/kvm exists.

  python3 tools/qemu-test.py phase1
  python3 tools/qemu-test.py phase2
  python3 tools/qemu-test.py all

phase1 expects a populated package cache (see cache-packages.sh) but still
works if packages have to be downloaded. The test user is qa / 1234, which
is the same in qwerty and colemak.
"""

from __future__ import annotations

import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

VM = Path("/mnt/gentoo/arch-install-vm")
CACHE = Path("/mnt/gentoo/arch-pkg-cache")
REPO = Path(__file__).resolve().parents[1]
ISO = VM / "archlinux-2026.09.01-x86_64.iso"
DISK = VM / "disk.qcow2"
HELPER = VM / "helper.raw"
VARS = VM / "ovmf-vars.fd"
OVMF_CODE = Path("/usr/share/edk2/x64/OVMF_CODE.4m.fd")
OVMF_VARS_SRC = Path("/usr/share/edk2/x64/OVMF_VARS.4m.fd")
SYSTEMD_BOOT = Path("/usr/lib/systemd/boot/efi/systemd-bootx64.efi")
DISK_SIZE = "40G"
# systemd and agetty color the prompt, so "root@archiso" is not contiguous on the wire.
_ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07|\x1b\(B|\x1b.")


def log(msg: str) -> None:
    print(msg, flush=True)


def run(cmd: list[str], **kwargs) -> None:
    subprocess.run(cmd, check=True, **kwargs)


def kvm_args() -> list[str]:
    if Path("/dev/kvm").exists():
        return ["-enable-kvm", "-cpu", "host"]
    return ["-cpu", "max"]


def ensure_disk(fresh: bool) -> None:
    VM.mkdir(parents=True, exist_ok=True)
    if fresh and DISK.exists():
        DISK.unlink()
    if not DISK.exists():
        run(["qemu-img", "create", "-f", "qcow2", str(DISK), DISK_SIZE])


def ensure_helper() -> None:
    if not ISO.is_file():
        raise SystemExit(f"Missing ISO: {ISO}")
    boot = VM / "iso-boot"
    if boot.exists():
        shutil.rmtree(boot)
    boot.mkdir()
    run(
        [
            "bsdtar",
            "-x",
            "-C",
            str(boot),
            "-f",
            str(ISO),
            "arch/boot/x86_64/vmlinuz-linux",
            "arch/boot/x86_64/initramfs-linux.img",
        ]
    )
    if HELPER.exists():
        HELPER.unlink()
    run(["truncate", "-s", "256M", str(HELPER)])
    run(["mkfs.fat", "-F", "32", str(HELPER)])
    env = os.environ.copy()
    env["MTOOLS_SKIP_CHECK"] = "1"

    def mtool(cmd: list[str]) -> None:
        run(cmd, env=env)

    for directory in ("::/EFI", "::/EFI/BOOT", "::/loader", "::/loader/entries"):
        mtool(["mmd", "-i", str(HELPER), directory])
    mtool(["mcopy", "-i", str(HELPER), str(SYSTEMD_BOOT), "::/EFI/BOOT/BOOTX64.EFI"])
    mtool(["mcopy", "-i", str(HELPER), str(boot / "arch/boot/x86_64/vmlinuz-linux"), "::/vmlinuz-linux"])
    mtool(
        [
            "mcopy",
            "-i",
            str(HELPER),
            str(boot / "arch/boot/x86_64/initramfs-linux.img"),
            "::/initramfs-linux.img",
        ]
    )
    loader = VM / "loader.conf"
    entry = VM / "archiso.conf"
    loader.write_text("default archiso\ntimeout 0\n")
    entry.write_text(
        "title Arch ISO\n"
        "linux /vmlinuz-linux\n"
        "initrd /initramfs-linux.img\n"
        "options archisobasedir=arch archisosearchuuid=2026-09-01-17-09-43-00 console=ttyS0,115200\n"
    )
    mtool(["mcopy", "-i", str(HELPER), str(loader), "::/loader/loader.conf"])
    mtool(["mcopy", "-i", str(HELPER), str(entry), "::/loader/entries/archiso.conf"])


def fresh_vars() -> None:
    shutil.copyfile(OVMF_VARS_SRC, VARS)


class Serial:
    def __init__(self, sock_path: Path, log_path: Path):
        self.sock_path = sock_path
        self.log = log_path.open("w", encoding="utf-8", errors="replace")
        self.buf = ""
        self.sock: socket.socket | None = None

    def connect(self, timeout: float = 30) -> None:
        deadline = time.time() + timeout
        last = ""
        while time.time() < deadline:
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.connect(str(self.sock_path))
                sock.setblocking(False)
                self.sock = sock
                return
            except (FileNotFoundError, ConnectionRefusedError) as exc:
                last = str(exc)
                time.sleep(0.2)
        raise SystemExit(f"serial socket did not come up: {last}")

    def _read_some(self) -> None:
        assert self.sock is not None
        try:
            chunk = self.sock.recv(4096)
        except BlockingIOError:
            return
        if not chunk:
            return
        text = chunk.decode("utf-8", "replace")
        self.buf += text
        self.log.write(text)
        self.log.flush()
        for line in text.splitlines():
            if any(token in line for token in ("==>", "INSTALL_", "COLEMAK_", "PHASE", "error:", "Error", "FAILED")):
                log(line)

    def wait_for(self, needles: list[str], timeout: float, start: int = 0) -> str:
        deadline = time.time() + timeout
        while time.time() < deadline:
            self._read_some()
            window = _ANSI.sub("", self.buf[start:])
            for needle in needles:
                if needle in window:
                    return needle
            time.sleep(0.2)
        tail = self.buf[-1500:]
        raise TimeoutError(f"timed out waiting for {needles}. tail:\n{tail}")

    def send(self, text: str) -> None:
        assert self.sock is not None
        self.sock.sendall(text.encode())

    def close(self) -> None:
        if self.sock is not None:
            self.sock.close()
        self.log.close()


def qemu_cmd(phase: str, sock: Path) -> list[str]:
    cmd = [
        "qemu-system-x86_64",
        "-machine",
        "q35",
        "-m",
        "5120",
        "-smp",
        "4",
        *kvm_args(),
        "-display",
        "none",
        "-monitor",
        "none",
        "-no-reboot",
        "-serial",
        f"unix:{sock},server,nowait",
        "-drive",
        f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
        "-drive",
        f"if=pflash,format=raw,file={VARS}",
        "-netdev",
        "user,id=net0",
        "-device",
        "virtio-net-pci,netdev=net0",
        "-device",
        "virtio-rng-pci",
        "-virtfs",
        f"local,path={CACHE},mount_tag=pkgcache,security_model=mapped,readonly=on",
    ]
    # bootindex belongs on the device, not on a qcow2 -drive.
    if phase == "phase1":
        cmd += [
            "-drive",
            f"file={DISK},format=qcow2,if=none,id=disk0",
            "-device",
            "virtio-blk-pci,drive=disk0,bootindex=1",
            "-drive",
            f"file={HELPER},format=raw,if=none,id=helper0",
            "-device",
            "virtio-blk-pci,drive=helper0,bootindex=0",
            "-drive",
            f"file={ISO},media=cdrom,readonly=on",
            "-virtfs",
            f"local,path={REPO},mount_tag=repo,security_model=mapped,readonly=on",
        ]
    else:
        cmd += [
            "-drive",
            f"file={DISK},format=qcow2,if=none,id=disk0",
            "-device",
            "virtio-blk-pci,drive=disk0,bootindex=0",
            "-virtfs",
            f"local,path={REPO},mount_tag=repo,security_model=mapped,readonly=on",
        ]
    return cmd


def launch(phase: str) -> tuple[subprocess.Popen, Serial]:
    sock = VM / f"{phase}.sock"
    if sock.exists():
        sock.unlink()
    serial = Serial(sock, VM / f"{phase}.log")
    qemu_log = (VM / f"{phase}-qemu.log").open("w")
    proc = subprocess.Popen(qemu_cmd(phase, sock), stdout=qemu_log, stderr=subprocess.STDOUT)
    serial.connect()
    return proc, serial


def phase1(fresh: bool) -> None:
    ensure_disk(fresh)
    ensure_helper()
    fresh_vars()
    log("Booting the live ISO in QEMU")
    proc, serial = launch("phase1")
    try:
        serial.wait_for(["archiso login:", "root@archiso"], 600)
        if "root@archiso" not in serial.buf:
            # Archiso's serial getty asks for root and accepts an empty password.
            # Some builds skip the password prompt and land on the shell directly.
            serial.send("root\n")
            mark = len(serial.buf)
            hit = serial.wait_for(["Password:", "root@archiso"], 90, start=mark)
            if hit == "Password:":
                serial.send("\n")
                serial.wait_for(["root@archiso"], 90)
        serial.send(
            "mkdir -p /mnt/repo /mnt/pkgcache && "
            "mount -t 9p -o trans=virtio,version=9p2000.L,msize=104857600,ro repo /mnt/repo && "
            "mount -t 9p -o trans=virtio,version=9p2000.L,msize=104857600,ro pkgcache /mnt/pkgcache && "
            "bash /mnt/repo/tools/guest-phase1.sh\n"
        )
        serial.wait_for(["INSTALL_BASE_OK", "INSTALL_BASE_FAIL"], 5400)
        if "INSTALL_BASE_FAIL" in serial.buf and "INSTALL_BASE_OK" not in serial.buf:
            raise SystemExit("stage 1 failed; see /mnt/gentoo/arch-install-vm/phase1.log")
        log("Stage 1 finished. Waiting for the VM to power off.")
        try:
            code = proc.wait(timeout=180)
            log(f"QEMU exited {code}")
        except subprocess.TimeoutExpired:
            proc.kill()
            log("VM did not power off; stopped it after INSTALL_BASE_OK.")
    finally:
        if proc.poll() is None:
            proc.kill()
        serial.close()


def phase2() -> None:
    if not DISK.exists():
        raise SystemExit(f"Missing {DISK}. Run phase1 first.")
    fresh_vars()
    log("Booting the installed system in QEMU")
    proc, serial = launch("phase2")
    try:
        serial.wait_for(["login:"], 600)
        serial.send("qa\n")
        mark = len(serial.buf)
        serial.wait_for(["Password:"], 90, start=mark)
        serial.send("1234\n")
        mark = len(serial.buf)
        # A first zsh login with no ~/.zshrc runs zsh-newuser-install and waits.
        hit = serial.wait_for(
            ["Type one of the keys", "archvm%", "qa@archvm"],
            90,
            start=mark,
        )
        if hit == "Type one of the keys":
            serial.send("q")
            mark = len(serial.buf)
            serial.wait_for(["archvm%", "qa@archvm", "% "], 60, start=mark)
        # The installed checkout is a copy from stage 1. Mount this repo and run
        # the current guest script so later fixes are what the VM executes.
        serial.send(
            ". ~/GitRepos/arch-install/secrets.sh; "
            "printf '%s\\n' \"$USER_PASSWORD\" | sudo -S -p '' mkdir -p /mnt/repo /mnt/pkgcache; "
            "printf '%s\\n' \"$USER_PASSWORD\" | sudo -S -p '' mount -t 9p "
            "-o trans=virtio,version=9p2000.L,msize=104857600,ro repo /mnt/repo; "
            "printf '%s\\n' \"$USER_PASSWORD\" | sudo -S -p '' mount -t 9p "
            "-o trans=virtio,version=9p2000.L,msize=104857600,ro pkgcache /mnt/pkgcache; "
            "bash /mnt/repo/tools/guest-phase2.sh\n"
        )
        mark = len(serial.buf)
        serial.wait_for(["COLEMAK_KC18="], 180, start=mark)
        conf = ""
        kc_line = ""
        for line in serial.buf[mark:].splitlines():
            if "COLEMAK_CONF=" in line:
                conf = line.split("COLEMAK_CONF=", 1)[1]
            if "COLEMAK_KC18=" in line:
                kc_line = line.split("COLEMAK_KC18=", 1)[1]
        if "colemak" not in conf:
            raise SystemExit(f"console keymap file is not colemak: {conf!r}")
        # dumpkeys: "keycode  18 = +f" under colemak, "+e" under qwerty.
        found = re.search(r"keycode\s+18\s*=\s*\+?(\S+)", kc_line)
        if not found or not found.group(1).startswith("f"):
            raise SystemExit(f"keycode 18 is not colemak f: {kc_line!r}")
        log(f"Colemak is active ({kc_line.strip()}). Waiting for stage 2.")
        serial.wait_for(["INSTALL_DESKTOP_OK", "INSTALL_DESKTOP_FAIL"], 28800)
        if "INSTALL_DESKTOP_FAIL" in serial.buf and "INSTALL_DESKTOP_OK" not in serial.buf:
            raise SystemExit("stage 2 failed; see /mnt/gentoo/arch-install-vm/phase2.log")
        log("Stage 2 finished.")
    finally:
        if proc.poll() is None:
            proc.kill()
        serial.close()


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in {"phase1", "phase2", "all"}:
        raise SystemExit("usage: qemu-test.py phase1|phase2|all")
    if not CACHE.is_dir():
        log(f"Package cache {CACHE} is missing. Official packages will be downloaded inside the VM.")
    step = sys.argv[1]
    if step in {"phase1", "all"}:
        phase1(fresh=True)
    if step in {"phase2", "all"}:
        phase2()


if __name__ == "__main__":
    main()
