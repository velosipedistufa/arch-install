#!/usr/bin/env python3
"""Home server at current ISP /64 + ::IID (prefix is dynamic, same as this PC)."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib import emit, g, home_server_v6, ping_host  # noqa: E402


def main() -> None:
    try:
        iid = int(g("HOME_SERVER_IID") or "6")
    except ValueError:
        iid = 6
    label = g("HOME_SERVER_LABEL") or f"::{iid}"
    host = home_server_v6(iid)
    if not host:
        emit(f"{label}○", "no global IPv6 prefix on a physical NIC", "crit")
        return
    ok, rtt = ping_host(host, ipv6=True, timeout=1.5)
    mark = "●" if ok else "○"
    cls = "ok" if ok else "crit"
    tooltip = f"{host} {'up' if ok else 'down'}"
    if rtt:
        tooltip += f"  {rtt} ms"
    emit(f"{label}{mark}", tooltip, cls)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        emit("?", str(exc), "crit")
