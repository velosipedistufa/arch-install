#!/usr/bin/env python3
"""Mihomo: up/down, TUN, country flag of egress IP. Prefer IPv6 geo. Cache by IP."""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib import cache_dir, curl, doh, emit, iso_flag, load_json, save_json  # noqa: E402

API = "http://[::1]:9093"
MIXED = "http://[::1]:7890"
GEO_FILE = cache_dir() / "geo.json"
GEO_TTL = 30 * 60


def api_get(path: str, timeout: float = 2.0) -> dict | None:
    req = urllib.request.Request(API + path)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return None


def tun_iface_up(name: str) -> bool:
    p = Path(f"/sys/class/net/{name}")
    if not p.exists():
        return False
    try:
        return (p / "operstate").read_text().strip() in ("up", "unknown")
    except OSError:
        return False


def egress_ip() -> str | None:
    """Egress as the VPN sees it (mixed-port), IPv6 first. DoH + --resolve avoids fake-ip."""
    v6s = doh("ifconfig.co", "AAAA")
    if v6s:
        ip = curl(
            "https://ifconfig.co/ip",
            timeout=3,
            resolve=f"ifconfig.co:443:{v6s[0]}",
            ipv6=True,
            proxy=MIXED,
        )
        if ip:
            return ip.strip()
    v4s = doh("ifconfig.co", "A")
    if v4s:
        ip = curl(
            "https://ifconfig.co/ip",
            timeout=3,
            resolve=f"ifconfig.co:443:{v4s[0]}",
            ipv6=False,
            proxy=MIXED,
        )
        if ip:
            return ip.strip()
    ip = curl("https://ifconfig.co/ip", timeout=3, proxy=MIXED)
    if ip:
        return ip.strip()
    ip = curl("https://ifconfig.co/ip", timeout=3)
    return ip.strip() if ip else None


def country_for(ip: str) -> str | None:
    # ipinfo returns a one-line ISO code at /country
    cc = curl(f"https://ipinfo.io/{ip}/country", timeout=3)
    if cc and len(cc.strip()) == 2 and cc.strip().isalpha():
        return cc.strip().upper()
    v6s = doh("ifconfig.co", "AAAA")
    resolve = f"ifconfig.co:443:{v6s[0]}" if v6s else None
    cc = curl("https://ifconfig.co/country-iso", timeout=3, resolve=resolve)
    if cc and len(cc.strip()) == 2 and cc.strip().isalpha():
        return cc.strip().upper()
    return None


def geo(ip: str) -> tuple[str, str]:
    cached = load_json(GEO_FILE) or {}
    now = time.time()
    if (
        cached.get("ip") == ip
        and cached.get("cc")
        and now - float(cached.get("ts") or 0) < GEO_TTL
    ):
        return cached["cc"], cached.get("flag") or iso_flag(cached["cc"])
    cc = country_for(ip) or ""
    flag = iso_flag(cc) if cc else ""
    save_json(GEO_FILE, {"ip": ip, "cc": cc, "flag": flag, "ts": now})
    return cc, flag


def main() -> None:
    cfg = api_get("/configs")
    if not cfg:
        emit("vpn --", "mihomo API [::1]:9093 unreachable", "down")
        return
    tun = cfg.get("tun") or {}
    tun_on = bool(tun.get("enable"))
    tun_dev = tun.get("device") or "Meta"
    iface_up = tun_iface_up(tun_dev)
    proxy = api_get("/proxies/PROXY") or {}
    node = proxy.get("now") or "?"

    ip = egress_ip()
    cc, flag = ("", "")
    if ip:
        cc, flag = geo(ip)

    glyph = flag or (cc if cc else "?")
    tun_mark = "●" if tun_on and iface_up else "○"
    text = f"{glyph}{tun_mark}"
    cls = "up" if tun_on and iface_up else "tun-off"
    tooltip = "\n".join(
        [
            f"mihomo {'up' if cfg else 'down'}",
            f"node: {node}",
            f"tun: {'on' if tun_on else 'off'} ({tun_dev} {'up' if iface_up else 'down'})",
            f"egress: {ip or 'unknown'}",
            f"geo: {cc or '?'}",
        ]
    )
    emit(text, tooltip, cls)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        emit("vpn --", str(exc), "down")
