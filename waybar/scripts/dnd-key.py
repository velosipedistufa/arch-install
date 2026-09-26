#!/usr/bin/env python3
"""Toggle do-not-disturb from the ZMK keyboard.

Super+Shift+N (keys already on the keymap: LMETA, LSHIFT, N).
F13 alone also toggles, if a later firmware maps a spare key to it.
"""

from __future__ import annotations

import glob
import os
import select
import struct
import subprocess
from pathlib import Path

# struct input_event on 64-bit: timeval (16) + type, code, value
EVENT = struct.Struct("llHHi")
EV_KEY = 0x01
KEY_LEFTSHIFT = 42
KEY_RIGHTSHIFT = 54
KEY_N = 49
KEY_LEFTMETA = 125
KEY_RIGHTMETA = 126
KEY_F13 = 183

TOGGLE = str(Path(__file__).with_name("dnd-toggle.sh"))


def keyboard() -> str:
    uniq = ""
    explicit = ""
    for path in (
        Path.home() / ".config/arch-install/globals.sh",
        Path("/home/alex/GitRepos/arch-install/globals.sh"),
    ):
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            if line.startswith("KEYBOARD_UNIQ="):
                uniq = line.split("=", 1)[1].strip().strip('"').strip("'")
            elif line.startswith("KEYBOARD_EVENT="):
                explicit = line.split("=", 1)[1].strip().strip('"').strip("'")
        if uniq or explicit:
            break
    if uniq:
        matches = sorted(glob.glob(f"/dev/input/by-id/*{uniq}*event-kbd"))
        if matches:
            return matches[0]
    if explicit and Path(explicit).exists():
        return explicit
    raise SystemExit("dnd-key: ZMK keyboard event node not found")


def toggle() -> None:
    subprocess.run([TOGGLE, "toggle"], check=False)


def main() -> None:
    path = keyboard()
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    down = set()
    buf = b""
    while True:
        ready, _, _ = select.select([fd], [], [], 1.0)
        if not ready:
            continue
        try:
            data = os.read(fd, EVENT.size * 64)
        except BlockingIOError:
            continue
        if not data:
            continue
        buf += data
        while len(buf) >= EVENT.size:
            _, _, typ, code, value = EVENT.unpack_from(buf)
            buf = buf[EVENT.size :]
            if typ != EV_KEY:
                continue
            if value == 1:
                down.add(code)
                meta = KEY_LEFTMETA in down or KEY_RIGHTMETA in down
                shift = KEY_LEFTSHIFT in down or KEY_RIGHTSHIFT in down
                if code == KEY_N and meta and shift:
                    toggle()
                elif code == KEY_F13:
                    toggle()
            elif value == 0:
                down.discard(code)


if __name__ == "__main__":
    main()
