#!/usr/bin/env python3
"""Waybar: bell when notifications are shown, dark bell-off in do-not-disturb."""

from __future__ import annotations

import json
import subprocess

ON = "\uf0f3"  # bell
OFF = "\uf1f6"  # bell-slash


def dnd() -> bool:
    try:
        out = subprocess.check_output(["makoctl", "mode"], text=True, timeout=1)
    except (subprocess.SubprocessError, OSError):
        return False
    return "do-not-disturb" in out.split()


def main() -> None:
    if dnd():
        payload = {
            "text": OFF,
            "tooltip": "Do not disturb — corner notifications hidden\nSuper+Shift+N or click to show them",
            "class": "dnd",
        }
    else:
        payload = {
            "text": ON,
            "tooltip": "Notifications on\nSuper+Shift+N or click for do not disturb",
            "class": "on",
        }
    print(json.dumps(payload))


if __name__ == "__main__":
    main()
