#!/usr/bin/env python3
"""Removable USB filesystems as JSON for the yazi usb plugin."""

from __future__ import annotations

import json
import subprocess


def main() -> None:
    raw = subprocess.check_output(
        [
            "lsblk",
            "-J",
            "-o",
            "NAME,PATH,LABEL,FSTYPE,TRAN,RM,HOTPLUG,MOUNTPOINT,TYPE,SIZE,MODEL",
        ],
        text=True,
    )
    data = json.loads(raw)
    vols = []
    for dev in data.get("blockdevices") or []:
        tran = (dev.get("tran") or "").lower()
        removable = str(dev.get("rm") or "") in {"1", "true", "True"} or dev.get("rm") is True
        if tran != "usb" and not removable:
            continue
        kids = dev.get("children") or []
        targets = kids or [dev]
        for part in targets:
            if kids and not part.get("fstype") and not part.get("mountpoint"):
                # Whole-disk row or an empty partition table entry.
                if part.get("type") == "disk":
                    continue
            if part.get("type") not in {None, "part", "disk", "rom"}:
                continue
            if not part.get("fstype") and not part.get("mountpoint"):
                continue
            mount = part.get("mountpoint") or ""
            label = part.get("label") or (dev.get("model") or "").strip() or part.get("name") or "usb"
            vols.append(
                {
                    "path": part.get("path") or f"/dev/{part.get('name')}",
                    "label": label,
                    "fstype": part.get("fstype") or "",
                    "mountpoint": mount,
                    "mounted": bool(mount),
                    "size": part.get("size") or "",
                }
            )
    print(json.dumps(vols))


if __name__ == "__main__":
    main()
