#!/usr/bin/env python3
"""VPS plate: DNS A/AAAA must match globals, then ping those addresses. DoH, never getent."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib import doh, emit, g, ping_host  # noqa: E402


def lamp(ok: bool, label: str) -> str:
    color = "#3dffb0" if ok else "#ff2a4a"
    return f'<span color="{color}">{label}</span>'


def main() -> None:
    name = g("VPS_HOST")
    if not name:
        emit("--", "VPS_HOST unset in secrets.sh", "down")
        return
    expect_a = g("VPS_A")
    expect_aaaa = g("VPS_AAAA")
    plate = g("VPS_LABEL") or "VPS"

    a_recs = doh(name, "A")
    aaaa_recs = doh(name, "AAAA")
    a_ok = (expect_a in a_recs) if expect_a else bool(a_recs)
    aaaa_ok = (expect_aaaa in aaaa_recs) if expect_aaaa else bool(aaaa_recs)
    v4 = expect_a or (a_recs[0] if a_recs else None)
    v6 = expect_aaaa or (aaaa_recs[0] if aaaa_recs else None)
    v4_ok, v4_rtt = (False, None)
    v6_ok, v6_rtt = (False, None)
    if v4:
        v4_ok, v4_rtt = ping_host(v4, ipv6=False, timeout=2.5)
    if v6:
        v6_ok, v6_rtt = ping_host(v6, ipv6=True, timeout=2.5)

    text = plate + " " + " ".join(
        [
            lamp(a_ok, "A"),
            lamp(aaaa_ok, "AAAA"),
            lamp(v4_ok, "v4"),
            lamp(v6_ok, "v6"),
        ]
    )
    oks = (a_ok, aaaa_ok, v4_ok, v6_ok)
    if all(oks):
        cls = "ok"
    elif any(oks):
        cls = "warn"
    else:
        cls = "crit"
    tooltip = "\n".join(
        [
            f"{plate} {name}",
            f"DNS A:    {'ok' if a_ok else 'fail'}  expect {expect_a or 'any'}  got {', '.join(a_recs) or '—'}",
            f"DNS AAAA: {'ok' if aaaa_ok else 'fail'}  expect {expect_aaaa or 'any'}  got {', '.join(aaaa_recs) or '—'}",
            f"IPv4:     {'ok' if v4_ok else 'fail'}" + (f"  {v4_rtt} ms" if v4_rtt else ""),
            f"IPv6:     {'ok' if v6_ok else 'fail'}" + (f" {v6_rtt} ms" if v6_rtt else ""),
            "DoH, not libc/fake-ip",
        ]
    )
    emit(text, tooltip, cls)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        emit("VPS --", str(exc), "crit")
